#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  // Subclassa a janela FILHA que o Flutter acabou de criar (a que ele
  // realmente usa para desenhar e para responder a WM_GETOBJECT) O MAIS
  // CEDO POSSÍVEL — antes de QUALQUER outra coisa que possa devolver o
  // controle para o Windows (RegisterPlugins, criar o method channel, e
  // principalmente SetChildContent() logo abaixo, que chama SetFocus()
  // na janela filha).
  //
  // Isso corrige uma condição de corrida que a versão anterior deste
  // arquivo tinha: ela fazia a subclassificação só DEPOIS de
  // SetChildContent(), ou seja, depois do SetFocus() nessa mesma janela.
  // Mudar o foco de teclado é exatamente o gatilho que o serviço de
  // teclado touch/painel de escrita à mão do Windows (que fica de olho
  // em qual controle de texto está em foco o tempo todo, mesmo sem
  // nenhum leitor de tela rodando — daemon liga por padrão em qualquer
  // Windows 10/11, com ou sem tela touch) usa para decidir se deve
  // sondar a janela com WM_GETOBJECT. Como esse SetFocus() já acontecia
  // ANTES de instalarmos o bloqueio, a sondagem chegava no WndProc
  // ORIGINAL do Flutter (não bloqueado ainda), ligava a árvore de
  // semântica (AXTree) — e, por ela não poder ser desligada de novo
  // durante a mesma sessão (ver comentário mais abaixo, no
  // ChildWindowProc), isso deixava CADA sessão do app vulnerável ao
  // crash desde os primeiros segundos, não só durante um
  // redimensionamento em si. Bate exatamente com o sintoma relatado: os
  // logs mostram erros de AXTree desde a conexão inicial da VM Service,
  // antes de qualquer redimensionamento ou interação do usuário.
  //
  // Subclassar aqui, antes de qualquer SetFocus (nosso ou de qualquer
  // outra coisa), fecha essa janela de corrida específica. Uma corrida
  // ainda menor permanece em teoria (entre a criação da janela filha,
  // que acontece dentro do construtor de FlutterViewController alguns
  // milissegundos atrás, e este ponto aqui) — essa parte não é possível
  // fechar sem reescrever o próprio motor do Flutter, é uma limitação
  // conhecida do motor (ver flutter/engine#43368), mas na prática é uma
  // janela de tempo muito menor do que a que existia antes.
  HWND child_hwnd = flutter_controller_->view()->GetNativeWindow();
  if (child_hwnd) {
    // Guarda o WndProc original numa propriedade da própria janela (em
    // vez de GWLP_USERDATA, que o Flutter já pode estar usando para
    // guardar o ponteiro da sua própria instância de view internamente —
    // sobrescrever isso quebraria o Flutter por completo).
    WNDPROC original = reinterpret_cast<WNDPROC>(
        GetWindowLongPtr(child_hwnd, GWLP_WNDPROC));
    SetProp(child_hwnd, L"SonoraOrigChildWndProc",
            reinterpret_cast<HANDLE>(original));
    SetWindowLongPtr(child_hwnd, GWLP_WNDPROC,
                      reinterpret_cast<LONG_PTR>(&FlutterWindow::ChildWindowProc));
  }

  RegisterPlugins(flutter_controller_->engine());

  // Canal (sem handler de chamadas Dart->C++; só usamos InvokeMethod
  // C++->Dart) para avisar o lado Dart assim que o usuário começa a
  // arrastar a borda da janela. WM_ENTERSIZEMOVE chega antes de qualquer
  // WM_SIZE — ou seja, antes de o redimensionamento em si acontecer.
  //
  // Isso existe porque reagir a um callback de "a janela JÁ mudou de
  // tamanho" (ex.: o listener onWindowResize do pacote window_manager,
  // que só dispara depois do primeiro WM_SIZE) chega tarde demais: o
  // primeiro "tick" do redimensionamento já aconteceu antes de a isolate
  // Dart sequer ser notificada, e é justamente nesse instante inicial
  // que o crash de resize costuma acontecer.
  resize_guard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "sonora/native_resize_guard",
          &flutter::StandardMethodCodec::GetInstance());

  // Botoes de midia na miniatura da barra de tarefas (hover no icone do
  // app). Canal proprio, "sonora/taskbar_media" -- ver
  // taskbar_media_controls.h e lib/core/utils/taskbar_media_controller.dart.
  taskbar_media_controls_ = std::make_unique<TaskbarMediaControls>(
      GetHandle(), flutter_controller_->engine()->messenger());

  // Só agora, com o bloqueio de WM_GETOBJECT já instalado, é seguro
  // chamar SetChildContent() (que por sua vez chama SetFocus() na
  // janela filha).
  SetChildContent(child_hwnd);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  taskbar_media_controls_ = nullptr;
  resize_guard_channel_ = nullptr;

  if (flutter_controller_) {
    HWND child_hwnd = flutter_controller_->view()->GetNativeWindow();
    if (child_hwnd) {
      // Desfaz a subclassificação antes de destruir, e limpa a
      // propriedade que guardava o WndProc original — deixar isso pra
      // trás seria um vazamento de memória do handle da propriedade.
      HANDLE original = GetProp(child_hwnd, L"SonoraOrigChildWndProc");
      if (original) {
        SetWindowLongPtr(child_hwnd, GWLP_WNDPROC,
                          reinterpret_cast<LONG_PTR>(original));
      }
      RemoveProp(child_hwnd, L"SonoraOrigChildWndProc");
    }
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT CALLBACK FlutterWindow::ChildWindowProc(HWND hwnd, UINT message,
                                                 WPARAM wparam,
                                                 LPARAM lparam) {
  // WM_GETOBJECT: é assim que o Windows (ou qualquer coisa rodando no
  // sistema com um cliente de UI Automation ativo — leitor de tela, mas
  // também o serviço de teclado touch/painel de escrita à mão que
  // acompanha dispositivos com caneta/toque, como uma mesa digitalizadora
  // Wacom, e que monitora campos de texto em foco o tempo todo,
  // independente de qualquer leitor de tela estar rodando) pede um
  // objeto de acessibilidade desta janela. É a JANELA FILHA que o
  // próprio Flutter cria para desenhar que responde a isso (não a nossa
  // janela de topo) — por isso a interceptação precisa estar aqui, e não
  // no MessageHandler de FlutterWindow.
  //
  // Se deixarmos isso chegar no WndProc original do Flutter, o motor
  // liga a árvore de semântica (AXTree) para responder — e é exatamente
  // aí que mora o crash nativo que vínhamos caçando (acesso inválido/
  // estouro de buffer dentro de flutter_windows.dll, sempre no mesmo
  // endereço, sempre relacionado a accessibility_bridge.cc). Pior: uma
  // vez ligada, essa árvore não tem como ser desligada de novo durante a
  // mesma sessão (limitação conhecida do próprio Flutter —
  // https://github.com/flutter/flutter/issues/3342), então qualquer
  // widget que reconstrua rápido (Slider, listas, grades) depois disso
  // vira um gatilho em potencial pro crash.
  //
  // Bloqueando aqui, o Flutter nunca fica sabendo que alguém pediu o
  // objeto de acessibilidade, então a árvore nunca é ligada e esse crash
  // inteiro deixa de poder acontecer. O custo: o app deixa de expor
  // informação de acessibilidade nativa pro Windows (leitor de tela não
  // vai conseguir ler o conteúdo) — uma troca deliberada, e a única
  // forma encontrada de manter o app estável sem depender de desligar
  // nada no sistema do usuário (caneta/toque incluídos).
  if (message == WM_GETOBJECT) {
    return 0;
  }

  HANDLE original = GetProp(hwnd, L"SonoraOrigChildWndProc");
  if (original) {
    return CallWindowProc(reinterpret_cast<WNDPROC>(original), hwnd, message,
                           wparam, lparam);
  }
  // Rede de segurança: se por algum motivo a propriedade não estiver
  // mais lá (não deveria acontecer), ao menos não trava a janela.
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void FlutterWindow::NotifyResizeGuard(bool starting) {
  if (!resize_guard_channel_) {
    return;
  }
  resize_guard_channel_->InvokeMethod(
      starting ? "resizeWillBegin" : "resizeDidEnd", nullptr);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // WM_GETOBJECT: é assim que o Windows (e qualquer ferramenta que sonde a
  // janela via UI Automation/MSAA — leitor de tela, lupa, mas também
  // overlays como Discord/GeForce Experience/RTSS/OBS) pede um objeto de
  // acessibilidade. Se deixarmos isso chegar no
  // flutter_controller_->HandleTopLevelWindowProc() abaixo, o motor do
  // Flutter liga a árvore de semântica (AXTree) para responder — e é
  // exatamente aí que mora o crash nativo que vínhamos caçando (accesso
  // inválido/estouro de buffer dentro de flutter_windows.dll, sempre no
  // mesmo endereço, sempre relacionado a accessibility_bridge.cc).
  //
  // Pior: uma vez ligada, essa árvore NÃO tem como ser desligada de novo
  // durante a mesma sessão (limitação conhecida do próprio Flutter —
  // https://github.com/flutter/flutter/issues/3342), então qualquer
  // widget que reconstrua rápido (Slider, listas, grades) depois disso
  // vira um gatilho em potencial pro crash, não só o que originou o
  // pedido.
  //
  // Interceptando aqui, ANTES de repassar pro Flutter, o motor nunca fica
  // sabendo que alguém pediu o objeto de acessibilidade, então a árvore
  // nunca é ligada e esse crash inteiro deixa de poder acontecer. O
  // custo: o app deixa de expor informação de acessibilidade nativa pro
  // Windows (leitor de tela não vai conseguir ler o conteúdo). É uma
  // troca deliberada — um app que não crasha em vez de um que crasha às
  // vezes mas seria acessível.
  if (message == WM_GETOBJECT) {
    return 0;
  }

  // Botoes de midia da miniatura da barra de tarefas: cliques
  // (WM_COMMAND/THBN_CLICKED) e a mensagem TaskbarButtonCreated, que avisa
  // que o Windows (re)criou o botao do app na barra e a toolbar precisa ser
  // adicionada de novo. Vem antes do Flutter/plugins de proposito: os cliques
  // dos nossos botoes nao sao de interesse de mais ninguem.
  if (taskbar_media_controls_) {
    LRESULT taskbar_result = 0;
    if (taskbar_media_controls_->HandleWindowMessage(message, wparam, lparam,
                                                     &taskbar_result)) {
      return taskbar_result;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_ENTERSIZEMOVE:
      // O usuário começou a arrastar a borda/título da janela (ou usou
      // "Mover ou Redimensionar" no menu de sistema). Ainda não houve
      // nenhuma mudança de tamanho — este é o ponto mais cedo possível
      // para avisar o Dart antes que isso comece.
      NotifyResizeGuard(true);
      break;
    case WM_EXITSIZEMOVE:
      // O gesto de redimensionar/mover terminou (usuário soltou o
      // mouse). Note que isto cobre arrastar a borda e o Aero Snap, mas
      // NÃO maximizar/restaurar por duplo-clique ou atalho de teclado —
      // esses casos continuam cobertos pelo listener onWindowResize do
      // window_manager no lado Dart, como uma rede de segurança
      // adicional.
      NotifyResizeGuard(false);
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
