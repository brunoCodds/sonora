#include "taskbar_media_controls.h"

#include <strsafe.h>

#include <cstdio>
#include <cwchar>
#include <utility>
#include <variant>
#include <vector>

#include <flutter/standard_method_codec.h>

namespace {

constexpr char kChannelName[] = "sonora/taskbar_media";

// Ordem dos botoes na toolbar. Os mais importantes vem primeiro porque, com
// pouco espaco, o Windows corta os botoes da direita para a esquerda.
// A mesma ordem do player do app (aleatorio, anterior, tocar, proxima,
// repetir): com 5 botoes o de tocar/pausar fica bem no centro.
enum ButtonIndex {
  kShuffle = 0,
  kPrevious = 1,
  kPlayPause = 2,
  kNext = 3,
  kRepeat = 4,
  kButtonCount = 5,
};

// Valor enviado ao Dart para cada botao (mesma ordem de ButtonIndex).
const char* const kButtonActions[kButtonCount] = {
    "shuffle",
    "previous",
    "playPause",
    "next",
    "repeat",
};

// IDs dos botoes (chegam em LOWORD(wParam) de um WM_COMMAND/THBN_CLICKED).
// Faixa propria para nao colidir com outros comandos da janela.
constexpr int kFirstButtonId = 41001;

// Depois de a janela voltar a ser exibida, reaplica os botoes uma vez mais
// com um pequeno atraso. Rede de seguranca caso o Windows recrie o botao da
// barra sem (ou antes de) mandar TaskbarButtonCreated -- ApplyButtons e
// idempotente, entao rodar a mais nao faz mal.
constexpr UINT_PTR kReapplyTimerId = 0x5A10;
constexpr UINT kReapplyDelayMs = 400;

bool ReadBool(const flutter::EncodableMap& map, const char* key,
              bool fallback) {
  const auto it = map.find(flutter::EncodableValue(std::string(key)));
  if (it == map.end()) {
    return fallback;
  }
  const bool* value = std::get_if<bool>(&it->second);
  return value ? *value : fallback;
}

std::string ReadString(const flutter::EncodableMap& map, const char* key) {
  const auto it = map.find(flutter::EncodableValue(std::string(key)));
  if (it == map.end()) {
    return std::string();
  }
  const std::string* value = std::get_if<std::string>(&it->second);
  return value ? *value : std::string();
}

}  // namespace

TaskbarMediaControls::TaskbarMediaControls(HWND window,
                                           flutter::BinaryMessenger* messenger)
    : window_(window),
      taskbar_created_message_(::RegisterWindowMessageW(L"TaskbarButtonCreated")),
      icon_directory_(ComputeIconDirectory()),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });
}

TaskbarMediaControls::~TaskbarMediaControls() {
  // Primeiro o canal, para nenhuma chamada Dart chegar a um objeto pela metade.
  channel_ = nullptr;

  if (window_) {
    ::KillTimer(window_, kReapplyTimerId);
  }
  if (taskbar_) {
    taskbar_->Release();
    taskbar_ = nullptr;
  }
  for (auto& entry : icon_cache_) {
    if (entry.second) {
      ::DestroyIcon(entry.second);
    }
  }
  icon_cache_.clear();
}

bool TaskbarMediaControls::HandleWindowMessage(UINT message, WPARAM wparam,
                                               LPARAM lparam,
                                               LRESULT* result) {
  // Mensagem registrada em tempo de execucao: nao cabe num "case".
  if (taskbar_created_message_ != 0 && message == taskbar_created_message_) {
    // O botao da barra de tarefas acabou de ser (re)criado: qualquer toolbar
    // anterior se perdeu com o botao antigo, entao e preciso adicionar de novo.
    taskbar_button_ready_ = true;
    buttons_added_ = false;
    ApplyButtons();
    return false;  // outros (ex.: plugins) tambem podem querer ver esta.
  }

  switch (message) {
    case WM_COMMAND:
      if (HIWORD(wparam) == THBN_CLICKED) {
        const int id = static_cast<int>(LOWORD(wparam));
        if (id >= kFirstButtonId && id < kFirstButtonId + kButtonCount) {
          NotifyButtonClicked(id - kFirstButtonId);
          *result = 0;
          return true;
        }
      }
      break;

    case WM_SHOWWINDOW:
      if (wparam != FALSE) {
        ::SetTimer(window_, kReapplyTimerId, kReapplyDelayMs, nullptr);
      }
      break;

    case WM_TIMER:
      if (wparam == kReapplyTimerId) {
        ::KillTimer(window_, kReapplyTimerId);
        ApplyButtons();
        *result = 0;
        return true;
      }
      break;

    case WM_SETTINGCHANGE:
      // O usuario trocou o tema claro/escuro do Windows: os icones precisam
      // trocar de cor para continuarem visiveis sobre o novo fundo.
      if (lparam != 0 &&
          std::wcscmp(reinterpret_cast<const wchar_t*>(lparam),
                      L"ImmersiveColorSet") == 0) {
        ApplyButtons();
      }
      break;
  }
  return false;
}

void TaskbarMediaControls::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() != "update") {
    result->NotImplemented();
    return;
  }

  const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
  if (arguments == nullptr) {
    result->Error("bad-arguments", "Esperava um mapa de argumentos.");
    return;
  }

  enabled_ = ReadBool(*arguments, "enabled", enabled_);
  playing_ = ReadBool(*arguments, "playing", playing_);
  shuffle_ = ReadBool(*arguments, "shuffle", shuffle_);

  const std::string repeat = ReadString(*arguments, "repeat");
  if (repeat == "all") {
    repeat_ = Repeat::kAll;
  } else if (repeat == "one") {
    repeat_ = Repeat::kOne;
  } else if (repeat == "off") {
    repeat_ = Repeat::kOff;
  }

  ApplyButtons();
  result->Success();
}

bool TaskbarMediaControls::EnsureTaskbarList() {
  if (taskbar_) {
    return true;
  }
  ITaskbarList3* list = nullptr;
  HRESULT hr = ::CoCreateInstance(CLSID_TaskbarList, nullptr,
                                  CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&list));
  if (FAILED(hr) || list == nullptr) {
    return false;
  }
  hr = list->HrInit();
  if (FAILED(hr)) {
    list->Release();
    return false;
  }
  taskbar_ = list;
  return true;
}

void TaskbarMediaControls::ApplyButtons() {
  // Antes do primeiro TaskbarButtonCreated o Windows nao permite chamar
  // metodos do ITaskbarList3.
  if (!taskbar_button_ready_ || window_ == nullptr) {
    return;
  }
  // Janela escondida (bandeja) = sem botao na barra = nada a atualizar.
  if (!::IsWindowVisible(window_)) {
    return;
  }
  if (!EnsureTaskbarList()) {
    return;
  }

  THUMBBUTTON buttons[kButtonCount];
  BuildButtons(buttons);

  if (buttons_added_) {
    if (SUCCEEDED(taskbar_->ThumbBarUpdateButtons(window_, kButtonCount,
                                                  buttons))) {
      failure_logged_ = false;
      return;
    }
    // Falhou: os botoes provavelmente se perderam sem aviso. Tenta adicionar
    // de novo logo abaixo.
    buttons_added_ = false;
  }

  HRESULT hr = taskbar_->ThumbBarAddButtons(window_, kButtonCount, buttons);
  if (SUCCEEDED(hr)) {
    buttons_added_ = true;
    failure_logged_ = false;
    return;
  }

  // Add falha se a toolbar ja existe (nosso flag pode ter dessincronizado).
  const HRESULT add_hr = hr;
  hr = taskbar_->ThumbBarUpdateButtons(window_, kButtonCount, buttons);
  buttons_added_ = SUCCEEDED(hr);
  if (buttons_added_) {
    failure_logged_ = false;
  } else {
    LogFailure(add_hr);
  }
}

void TaskbarMediaControls::LogFailure(HRESULT hr) {
#ifdef _DEBUG
  // Uma vez por sequencia de falhas (nao a cada atualizacao de estado). E
  // esperado falhar enquanto a janela esta no modo mini (sem botao na barra
  // de tarefas); se os botoes NAO aparecem com a janela cheia, o HRESULT
  // abaixo e a pista.
  if (failure_logged_) {
    return;
  }
  failure_logged_ = true;
  std::fprintf(stderr,
               "[taskbar-media] nao foi possivel aplicar os botoes "
               "(HRESULT 0x%08lX). Esperado no modo mini/oculto.\n",
               static_cast<unsigned long>(hr));
#else
  (void)hr;
#endif
}

void TaskbarMediaControls::BuildButtons(THUMBBUTTON* buttons) {
  // O painel de miniaturas segue o tema do SISTEMA (nao o dos apps): fundo
  // escuro -> icones claros ("_dark"), fundo claro -> icones escuros ("_light").
  const wchar_t* theme = IsSystemLightTheme() ? L"_light" : L"_dark";

  const wchar_t* glyphs[kButtonCount];
  const wchar_t* tooltips[kButtonCount];

  glyphs[kShuffle] = shuffle_ ? L"shuffle_on" : L"shuffle_off";
  tooltips[kShuffle] =
      shuffle_ ? L"Aleat\u00f3rio: ativado" : L"Aleat\u00f3rio: desativado";

  glyphs[kPrevious] = L"previous";
  tooltips[kPrevious] = L"Anterior";

  glyphs[kPlayPause] = playing_ ? L"pause" : L"play";
  tooltips[kPlayPause] = playing_ ? L"Pausar" : L"Tocar";

  glyphs[kNext] = L"next";
  tooltips[kNext] = L"Pr\u00f3xima";

  switch (repeat_) {
    case Repeat::kAll:
      glyphs[kRepeat] = L"repeat_all";
      tooltips[kRepeat] = L"Repetir: toda a fila";
      break;
    case Repeat::kOne:
      glyphs[kRepeat] = L"repeat_one";
      tooltips[kRepeat] = L"Repetir: esta m\u00fasica";
      break;
    case Repeat::kOff:
    default:
      glyphs[kRepeat] = L"repeat_off";
      tooltips[kRepeat] = L"Repetir: desativado";
      break;
  }

  for (int i = 0; i < kButtonCount; ++i) {
    ZeroMemory(&buttons[i], sizeof(THUMBBUTTON));

    const std::wstring icon_name =
        std::wstring(L"taskbar_") + glyphs[i] + theme;
    const HICON icon = GetIcon(icon_name);

    DWORD mask = THB_TOOLTIP | THB_FLAGS;
    if (icon != nullptr) {
      mask |= THB_ICON;
      buttons[i].hIcon = icon;
    }
    buttons[i].dwMask = static_cast<THUMBBUTTONMASK>(mask);
    buttons[i].iId = static_cast<UINT>(kFirstButtonId + i);
    // Sem musica na fila os botoes aparecem desabilitados (apagados), como
    // no Windows Media Player, em vez de sumirem.
    buttons[i].dwFlags = enabled_ ? THBF_ENABLED : THBF_DISABLED;
    StringCchCopyW(buttons[i].szTip, ARRAYSIZE(buttons[i].szTip), tooltips[i]);
  }
}

void TaskbarMediaControls::NotifyButtonClicked(int index) {
  if (!channel_ || index < 0 || index >= kButtonCount) {
    return;
  }
  channel_->InvokeMethod(
      "button", std::make_unique<flutter::EncodableValue>(
                    std::string(kButtonActions[index])));
}

HICON TaskbarMediaControls::GetIcon(const std::wstring& name) {
  // Tamanho "pequeno" do sistema para o DPI desta janela (16px a 100%, 24px
  // a 150%, ...). O mesmo .ico traz varios tamanhos e o LoadImage escolhe o
  // mais proximo do pedido.
  UINT dpi = ::GetDpiForWindow(window_);
  if (dpi == 0) {
    dpi = 96;
  }
  const int size = ::GetSystemMetricsForDpi(SM_CXSMICON, dpi);

  const std::wstring key = name + L"@" + std::to_wstring(size);
  const auto cached = icon_cache_.find(key);
  if (cached != icon_cache_.end()) {
    return cached->second;
  }
  if (icon_directory_.empty()) {
    return nullptr;
  }

  const std::wstring path = icon_directory_ + L"\\" + name + L".ico";
  HICON icon = static_cast<HICON>(::LoadImageW(nullptr, path.c_str(), IMAGE_ICON,
                                               size, size, LR_LOADFROMFILE));
  if (icon != nullptr) {
    // So guarda sucessos: se o arquivo faltar, tenta de novo na proxima vez
    // em vez de ficar sem icone para sempre.
    icon_cache_[key] = icon;
  }
  return icon;
}

// static
bool TaskbarMediaControls::IsSystemLightTheme() {
  DWORD value = 0;
  DWORD value_size = sizeof(value);
  const LSTATUS status = ::RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"SystemUsesLightTheme", RRF_RT_REG_DWORD, nullptr, &value, &value_size);
  // Sem a chave (Windows antigo / valor ausente), assume tema escuro.
  return status == ERROR_SUCCESS && value != 0;
}

// static
std::wstring TaskbarMediaControls::ComputeIconDirectory() {
  std::vector<wchar_t> buffer(32768);
  const DWORD length = ::GetModuleFileNameW(
      nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  if (length == 0 || length >= buffer.size()) {
    return std::wstring();
  }
  std::wstring path(buffer.data(), length);
  const size_t last_slash = path.find_last_of(L"\\/");
  if (last_slash == std::wstring::npos) {
    return std::wstring();
  }
  path.resize(last_slash);
  // Os assets declarados no pubspec (assets/icons/) ficam aqui, ao lado do
  // .exe, tanto em debug quanto em release.
  return path + L"\\data\\flutter_assets\\assets\\icons";
}
