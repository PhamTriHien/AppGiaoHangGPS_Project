#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdio>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  wchar_t exe_path[MAX_PATH];
  if (::GetModuleFileNameW(nullptr, exe_path, MAX_PATH) > 0) {
    wchar_t *last_slash = wcsrchr(exe_path, L'\\');
    if (last_slash != nullptr) {
      *last_slash = L'\0';
      ::SetCurrentDirectoryW(exe_path);
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  std::wstring window_title = L"He Thong Giao Hang Dinh Vi GPS Da Nen Tang";
  int win_x = 40;
  int win_y = 30;
  int win_w = 1440;
  int win_h = 860;
  for (const auto& arg : command_line_arguments) {
    if (arg.rfind("--window-title=", 0) == 0) {
      std::string raw_title = arg.substr(15);
      if (!raw_title.empty()) {
        int needed = ::MultiByteToWideChar(CP_UTF8, 0, raw_title.c_str(), -1,
                                           nullptr, 0);
        if (needed > 1) {
          std::wstring converted(needed - 1, L'\0');
          ::MultiByteToWideChar(CP_UTF8, 0, raw_title.c_str(), -1,
                                &converted[0], needed);
          window_title = converted;
        }
      }
    } else if (arg.rfind("--window-bounds=", 0) == 0) {
      int bx = 0;
      int by = 0;
      int bw = 0;
      int bh = 0;
      if (sscanf_s(arg.c_str() + 16, "%d,%d,%d,%d", &bx, &by, &bw, &bh) == 4 &&
          bw >= 360 && bh >= 400) {
        win_x = bx;
        win_y = by;
        win_w = bw;
        win_h = bh;
      }
    }
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(win_x, win_y);
  Win32Window::Size size(static_cast<unsigned int>(win_w),
                         static_cast<unsigned int>(win_h));
  if (!window.Create(window_title, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  HWND hwnd = window.GetHandle();
  if (hwnd != nullptr) {
    ::ShowWindow(hwnd, SW_RESTORE);
    ::ShowWindow(hwnd, SW_SHOW);
    ::BringWindowToTop(hwnd);
    ::SetForegroundWindow(hwnd);
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
