// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_RUNNER_WIN32_WINDOW_H_
#define FLUTTER_RUNNER_WIN32_WINDOW_H_

#include <windows.h>
#include <windowsx.h>

#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // sizes are specified to the OS in physical pixels, hence to ensure a
  // consistent size to will treat the DPI scaling factor as 100%.
  // Returns true if the window was created successfully.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Show the current window. Returns true if the window was successfully shown.
  bool Show();

  // Release the OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle, or null if window has been destroyed.
  HWND GetHandle() { return window_handle_; }

  // Sets |quit_on_close| to true and destroys the window when WM_CLOSE is
  // received.
  void SetQuitOnClose(bool quit_on_close);

  // Returns a RECT representing the bounds of the current client area.
  RECT GetClientArea();

 protected:
  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can do to modify behavior without dealing with actual
  // message punmping. Returns true if message was handled.
  virtual bool OnCreate();

  // Called when window has been destroyed.
  virtual void OnDestroy();

  // Called when the window's DPI is changed.
  virtual void OnDpiScale(unsigned int dpi);

  // Called when the window's size is changed.
  virtual void OnResize(unsigned int width, unsigned int height);

  // Called when a key is pressed while the window has focus.
  virtual void OnKey(UINT const message, WPARAM const wparam,
                     LPARAM const lparam);

  // Called when text input is received while the window has focus.
  virtual void OnCharacter(wchar_t character);

  // Called when the pointer has moved or a button event occurs.
  virtual void OnPointerMove(int32_t x, int32_t y);

  // Called when the pointer is down.
  virtual void OnPointerDown(int32_t x, int32_t y, UINT button);

  // Called when the pointer is up.
  virtual void OnPointerUp(int32_t x, int32_t y, UINT button);

  // Called when the pointer leaves the window.
  virtual void OnPointerLeave();

  // Called when scrolling with a mouse wheel.
  virtual void OnScroll(double x_offset, double y_offset, int32_t x, int32_t y);

  // Processes all window messages received by this window.
  // Called by subclass's custom window procedure. LRESULT is the value
  // returned from the window procedure.
  virtual LRESULT MessageHandler(HWND window, UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

 private:
  // static callback called during creation.
  friend LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Creates a new Win32Window::Point from |x| and |y|.
  static Point GetPointFromLparam(LPARAM lparam);

  // Updates the window theme to dark mode.
  void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // window handle for top-level window.
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  HWND child_content_ = nullptr;
};

#endif  // FLUTTER_RUNNER_WIN32_WINDOW_H_
