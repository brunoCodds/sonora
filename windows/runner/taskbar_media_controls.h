#ifndef RUNNER_TASKBAR_MEDIA_CONTROLS_H_
#define RUNNER_TASKBAR_MEDIA_CONTROLS_H_

#include <windows.h>
#include <shobjidl.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <map>
#include <memory>
#include <string>

// Botoes de midia (anterior / tocar-pausar / proxima / repetir) no painel
// que aparece ao passar o mouse sobre o icone do app na barra de tarefas do
// Windows -- o mesmo painel que o Spotify e o Windows Media Player usam.
//
// IMPORTANTE: isto NAO e o SMTC (System Media Transport Controls). O SMTC
// alimenta o cartao de midia do volume/tela de bloqueio e as teclas de
// midia, mas nao desenha nada na miniatura da barra de tarefas. O que
// desenha botoes ali e a "thumbnail toolbar" do ITaskbarList3 (maximo de 7
// botoes, o que deixa espaco de sobra para o botao de repetir).
//
// Divisao de trabalho com o lado Dart (lib/core/utils/
// taskbar_media_controller.dart), pelo canal "sonora/taskbar_media":
//   Dart -> C++  "update"   {enabled: bool, playing: bool, shuffle: bool,
//                            repeat: "off"|"all"|"one"}
//                 Estado atual do player; aqui so desenhamos os botoes.
//   C++ -> Dart  "button"   "shuffle" | "previous" | "playPause" | "next" |
//                           "repeat"
//                 O usuario clicou num botao; quem decide o que fazer e o Dart.
//
// Por que isto mora no runner e nao num pacote (ex.: windows_taskbar): a
// Sonora esconde a janela na bandeja e alterna setSkipTaskbar, o que faz o
// Windows DESTRUIR e RECRIAR o botao da barra de tarefas -- e a toolbar de
// miniatura se perde junto. O Windows avisa a recriacao com a mensagem
// registrada "TaskbarButtonCreated"; aqui ela e tratada e os botoes sao
// adicionados de novo com o ultimo estado conhecido. Pacotes que guardam
// "ja adicionei os botoes" para sempre nao se recuperam disso.
class TaskbarMediaControls {
 public:
  TaskbarMediaControls(HWND window, flutter::BinaryMessenger* messenger);
  ~TaskbarMediaControls();

  TaskbarMediaControls(const TaskbarMediaControls&) = delete;
  TaskbarMediaControls& operator=(const TaskbarMediaControls&) = delete;

  // Deve ser chamado pelo MessageHandler da janela para TODA mensagem.
  // Retorna true quando a mensagem foi consumida (nesse caso o valor em
  // |result| deve ser devolvido ao Windows); false para seguir o fluxo
  // normal (inclusive para as mensagens que so observamos).
  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam,
                           LRESULT* result);

 private:
  enum class Repeat { kOff, kAll, kOne };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Cria (uma vez) o ITaskbarList3. Retorna false se nao foi possivel.
  bool EnsureTaskbarList();


  // Empurra o estado atual para a toolbar: ThumbBarAddButtons na primeira
  // vez (ou depois de o Windows recriar o botao) e ThumbBarUpdateButtons
  // nas seguintes. Nao faz nada se o botao da barra ainda nao existe ou se
  // a janela esta oculta (ex.: escondida na bandeja); quando ela voltar, o
  // Windows manda TaskbarButtonCreated e isto roda de novo.
  void ApplyButtons();

  void BuildButtons(THUMBBUTTON* buttons);
  void LogFailure(HRESULT hr);
  void NotifyButtonClicked(int index);

  // Carrega (e guarda em cache, pelo resto da sessao) um .ico de
  // <exe>/data/flutter_assets/assets/icons. Os HICON ficam vivos de
  // proposito: nao ha garantia documentada de que o shell copie o icone
  // passado em THUMBBUTTON, e sao so alguns KB no total.
  HICON GetIcon(const std::wstring& name);

  static bool IsSystemLightTheme();
  static std::wstring ComputeIconDirectory();

  HWND window_;
  UINT taskbar_created_message_;
  std::wstring icon_directory_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  ITaskbarList3* taskbar_ = nullptr;
  std::map<std::wstring, HICON> icon_cache_;

  // Ja recebemos TaskbarButtonCreated ao menos uma vez (so a partir dai e
  // permitido chamar metodos do ITaskbarList3).
  bool taskbar_button_ready_ = false;
  // ThumbBarAddButtons ja foi bem-sucedido para o botao atual da barra.
  bool buttons_added_ = false;
  // Evita repetir o mesmo log de falha (so em build Debug) a cada update.
  bool failure_logged_ = false;

  // Ultimo estado recebido do Dart. Comeca "desabilitado" para que, se o
  // Windows avisar que o botao foi criado antes de o Dart mandar qualquer
  // coisa, os botoes ja aparecam (apagados) em vez de faltar.
  bool enabled_ = false;
  bool playing_ = false;
  bool shuffle_ = false;
  Repeat repeat_ = Repeat::kOff;
};

#endif  // RUNNER_TASKBAR_MEDIA_CONTROLS_H_
