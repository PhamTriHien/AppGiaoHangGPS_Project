#include "flutter_window.h"

#include <shellapi.h>

#include <cstring>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayIconId = 1001;

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int count = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                    static_cast<int>(utf8.size()), nullptr, 0);
  if (count <= 0) return std::wstring();
  std::wstring wide(static_cast<size_t>(count), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        wide.data(), count);
  return wide;
}

void CopyWideTruncated(wchar_t* dest, size_t capacity,
                       const std::wstring& source) {
  if (capacity == 0) return;
  size_t len = source.size();
  if (len >= capacity) {
    len = capacity - 1;
    if (len > 0 && source[len - 1] >= 0xD800 && source[len - 1] <= 0xDBFF) {
      --len;
    }
  }
  if (len > 0) {
    std::memcpy(dest, source.data(), len * sizeof(wchar_t));
  }
  dest[len] = L'\0';
}

std::string ReadStringArg(const flutter::EncodableMap& args,
                          const char* key) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it != args.end() && std::holds_alternative<std::string>(it->second)) {
    return std::get<std::string>(it->second);
  }
  return std::string();
}

}  // namespace

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
  RegisterPlugins(flutter_controller_->engine());
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "ghst/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "focus") {
          HWND hwnd = GetHandle();
          if (hwnd != nullptr) {
            ::ShowWindow(hwnd, ::IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
            ::SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                           SWP_NOMOVE | SWP_NOSIZE);
            ::SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                           SWP_NOMOVE | SWP_NOSIZE);
            ::BringWindowToTop(hwnd);
            ::SetForegroundWindow(hwnd);
          }
          result->Success();
          return;
        }
        if (call.method_name() == "areNotificationsEnabled" ||
            call.method_name() == "requestNotificationPermission") {
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name() == "showLocalNotification") {
          HWND hwnd = GetHandle();
          if (hwnd == nullptr || call.arguments() == nullptr ||
              !std::holds_alternative<flutter::EncodableMap>(
                  *call.arguments())) {
            result->Success(flutter::EncodableValue(false));
            return;
          }
          const auto& args =
              std::get<flutter::EncodableMap>(*call.arguments());
          std::string title_utf8 = ReadStringArg(args, "title");
          if (title_utf8.empty()) title_utf8 = "GHST EXPRESS";
          std::string body_utf8 = ReadStringArg(args, "body");
          if (body_utf8.empty()) {
            result->Success(flutter::EncodableValue(false));
            return;
          }

          NOTIFYICONDATAW nid = {};
          nid.cbSize = sizeof(NOTIFYICONDATAW);
          nid.hWnd = hwnd;
          nid.uID = kTrayIconId;
          nid.uFlags = NIF_ICON | NIF_TIP | NIF_INFO;
          nid.hIcon = ::LoadIcon(::GetModuleHandle(nullptr),
                                 MAKEINTRESOURCE(IDI_APP_ICON));
          if (nid.hIcon == nullptr) {
            nid.hIcon = ::LoadIcon(nullptr, IDI_APPLICATION);
          }
          CopyWideTruncated(nid.szTip, ARRAYSIZE(nid.szTip),
                            L"GHST EXPRESS");
          CopyWideTruncated(nid.szInfoTitle, ARRAYSIZE(nid.szInfoTitle),
                            Utf8ToWide(title_utf8));
          CopyWideTruncated(nid.szInfo, ARRAYSIZE(nid.szInfo),
                            Utf8ToWide(body_utf8));
          nid.dwInfoFlags = NIIF_INFO;

          BOOL ok = FALSE;
          if (!tray_icon_added_) {
            ok = ::Shell_NotifyIconW(NIM_ADD, &nid);
            if (ok) tray_icon_added_ = true;
          } else {
            ok = ::Shell_NotifyIconW(NIM_MODIFY, &nid);
            if (!ok) {
              ok = ::Shell_NotifyIconW(NIM_ADD, &nid);
              tray_icon_added_ = (ok == TRUE);
            }
          }
          result->Success(flutter::EncodableValue(ok == TRUE));
          return;
        }
        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  if (tray_icon_added_ && GetHandle() != nullptr) {
    NOTIFYICONDATAW nid = {};
    nid.cbSize = sizeof(NOTIFYICONDATAW);
    nid.hWnd = GetHandle();
    nid.uID = kTrayIconId;
    ::Shell_NotifyIconW(NIM_DELETE, &nid);
    tray_icon_added_ = false;
  }
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
