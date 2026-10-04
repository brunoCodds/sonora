#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "taskbar_media_controls.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Canal usado para avisar o lado Dart, o mais cedo possível, quando um
  // redimensionamento interativo da janela (arrastar borda) começa ou
  // termina. Ver comentário sobre NotifyResizeGuard() no .cpp para o
  // motivo de isso existir em vez de só depender de um listener Dart de
  // "a janela mudou de tamanho".
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      resize_guard_channel_;

  // Botoes de midia (anterior / tocar-pausar / proxima / repetir) no painel
  // de miniatura da barra de tarefas. Recebe as mensagens da janela via
  // MessageHandler (ver taskbar_media_controls.h para o porque de isto
  // morar aqui em vez de num pacote).
  std::unique_ptr<TaskbarMediaControls> taskbar_media_controls_;

  // WndProc que instalamos na janela filha do Flutter no lugar da
  // original, só para poder interceptar WM_GETOBJECT antes que o
  // Flutter a veja. Precisa ser uma função "livre" (assinatura C de
  // WndProc do Win32), não um método de instância — por isso é static.
  // O WndProc original é recuperado via GetProp(hwnd,
  // L"SonoraOrigChildWndProc") dentro dela mesma, não guardado aqui.
  static LRESULT CALLBACK ChildWindowProc(HWND hwnd, UINT message,
                                           WPARAM wparam, LPARAM lparam);

  // Notifica o lado Dart (via |resize_guard_channel_|) que um
  // redimensionamento interativo está começando (|starting| = true) ou
  // terminando (|starting| = false). Não faz nada se o canal ainda não
  // estiver pronto (ex.: mensagem chegando antes de OnCreate terminar).
  void NotifyResizeGuard(bool starting);
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
