#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shlwapi.h>
#include <wrl.h>
#include <memory>
#include <string>
#include <algorithm>
#include <deque>
#include "Vendor/WebView2.h"
#ifdef OMNICLOCK_UI_REVIEW
#include "Vendor/WebView2EnvironmentOptions.h"
#endif
#include "include/WinWebView.h"
#include "../Win32Shim/include/winshim.h"
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Callback;
static std::wstring wide(const char *s) { if(!s)return {}; int n=MultiByteToWideChar(CP_UTF8,0,s,-1,nullptr,0);std::wstring v(n? n-1:0,L'\0');if(n>1)MultiByteToWideChar(CP_UTF8,0,s,-1,&v[0],n);return v; }
static std::string utf8(const wchar_t *s) { if(!s)return {};int n=WideCharToMultiByte(CP_UTF8,0,s,-1,nullptr,0,nullptr,nullptr);std::string v(n?n-1:0,'\0');if(n>1)WideCharToMultiByte(CP_UTF8,0,s,-1,&v[0],n,nullptr,nullptr);return v; }
struct WebWindow {
 HWND hwnd=nullptr;std::string key,url;std::wstring assets,profile,script;omni_web_callback callback=nullptr;void*context=nullptr;
 std::deque<std::string> messages;
 ComPtr<ICoreWebView2Controller> controller;ComPtr<ICoreWebView2> web;std::string pending;double opacity=1;bool ready=false,closed=false;int minWidth=360,minHeight=320;
 void emit(const std::string &s){if(callback&&!closed)callback(context,key.c_str(),s.c_str());}
 bool permits(const wchar_t *source) const {
  std::wstring s=source?source:L"";
  if(url.rfind("https://omniclock.local/",0)==0)return s.rfind(L"https://omniclock.local/",0)==0;
  if(url.rfind("https://www.ailyre.com/tokenclock/network-check/",0)==0)return s.rfind(L"https://www.ailyre.com/tokenclock/network-check/",0)==0;
  if(url.rfind("http://127.0.0.1:",0)==0){auto end=url.find('/',7);auto origin=url.substr(0,end)+"/";return s.rfind(wide(origin.c_str()),0)==0;}
  return false;
 }
};
using Holder=std::shared_ptr<WebWindow>;
static Holder get(HWND hwnd){auto p=reinterpret_cast<Holder*>(GetWindowLongPtrW(hwnd,GWLP_USERDATA));return p?*p:nullptr;}
static void resize(const Holder&s){if(s&&s->controller&&IsWindow(s->hwnd)){RECT r{};GetClientRect(s->hwnd,&r);s->controller->put_Bounds(r);}}
static LRESULT CALLBACK procedure(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp){
 auto s=get(hwnd);
 if(msg==WM_NCCREATE){auto c=reinterpret_cast<CREATESTRUCTW*>(lp);SetWindowLongPtrW(hwnd,GWLP_USERDATA,(LONG_PTR)c->lpCreateParams);s=get(hwnd);s->hwnd=hwnd;}
 switch(msg){
 case WM_APP+90:if(s&&!s->messages.empty()){auto message=std::move(s->messages.front());s->messages.pop_front();s->emit(message);}return 0;
 case WM_SIZE:resize(s);return 0;
 case WM_DPICHANGED:{auto r=(RECT*)lp;SetWindowPos(hwnd,nullptr,r->left,r->top,r->right-r->left,r->bottom-r->top,SWP_NOZORDER|SWP_NOACTIVATE);resize(s);return 0;}
 case WM_EXITSIZEMOVE:if(s){RECT r{};GetWindowRect(hwnd,&r);UINT dpi=GetDpiForWindow(hwnd);s->emit("{\"event\":\"sizeChanged\",\"width\":"+std::to_string(MulDiv(r.right-r.left,96,dpi?dpi:96))+",\"height\":"+std::to_string(MulDiv(r.bottom-r.top,96,dpi?dpi:96))+"}");}return 0;
 case WM_GETMINMAXINFO:if(s){auto m=(MINMAXINFO*)lp;UINT dpi=GetDpiForWindow(hwnd);m->ptMinTrackSize={MulDiv(s->minWidth,dpi?dpi:96,96),MulDiv(s->minHeight,dpi?dpi:96,96)};}return 0;
 case WM_THEMECHANGED:case WM_SETTINGCHANGE:if(s)win_fluent_apply(hwnd,WIN_FLUENT_ACRYLIC);break;
 case WM_ERASEBKGND:return 1;
 case WM_PAINT:{PAINTSTRUCT ps{};auto dc=BeginPaint(hwnd,&ps);RECT r{};GetClientRect(hwnd,&r);win_fluent_diagnostics d{};d.struct_size=sizeof(d);win_fluent_get_diagnostics(hwnd,&d);if(d.applied_material)FillRect(dc,&r,(HBRUSH)GetStockObject(BLACK_BRUSH));else win_fluent_paint_fallback(hwnd,dc,&r);EndPaint(hwnd,&ps);return 0;}
 case WM_CLOSE:ShowWindow(hwnd,SW_HIDE);if(s)s->emit("{\"event\":\"hidden\"}");return 0;
 case WM_NCDESTROY:if(s){s->emit("{\"event\":\"closed\"}");s->closed=true;if(s->controller)s->controller->Close();s->web.Reset();s->controller.Reset();win_fluent_forget(hwnd);}delete reinterpret_cast<Holder*>(GetWindowLongPtrW(hwnd,GWLP_USERDATA));SetWindowLongPtrW(hwnd,GWLP_USERDATA,0);break;
 }
 return DefWindowProcW(hwnd,msg,wp,lp);
}
void omni_web_initialize(void){CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);}
void*omni_web_open(const char*key,const char*title,const char*assets,const char*profile,const char*url,const char*startup,int width,int height,omni_web_callback callback,void*context){
 static bool registered=false;
 if(!registered){WNDCLASSEXW wc{};wc.cbSize=sizeof(wc);wc.lpfnWndProc=procedure;wc.hInstance=GetModuleHandleW(nullptr);wc.hCursor=LoadCursorW(nullptr,IDC_ARROW);wc.lpszClassName=L"OmniClockFluentWindow";RegisterClassExW(&wc);registered=true;}
 auto s=std::make_shared<WebWindow>();s->key=key?key:"";s->url=url?url:"";s->assets=wide(assets);s->profile=wide(profile);s->script=wide(startup);s->callback=callback;s->context=context;if(s->key=="details")s->minWidth=320;
 UINT dpi=GetDpiForWindow((HWND)win_self());if(!dpi)dpi=GetDpiForSystem();
 width=MulDiv(width,dpi,96);height=MulDiv(height,dpi,96);
 MONITORINFO monitor{sizeof(monitor)};GetMonitorInfoW(MonitorFromWindow((HWND)win_self(),MONITOR_DEFAULTTONEAREST),&monitor);
 width=std::min(width,(int)(monitor.rcWork.right-monitor.rcWork.left)-16);height=std::min(height,(int)(monitor.rcWork.bottom-monitor.rcWork.top)-16);
 HWND hwnd=CreateWindowExW(WS_EX_TOOLWINDOW,L"OmniClockFluentWindow",wide(title).c_str(),WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,width,height,(HWND)win_self(),nullptr,GetModuleHandleW(nullptr),new Holder(s));
 if(!hwnd)return nullptr;win_fluent_apply(hwnd,WIN_FLUENT_ACRYLIC);ShowWindow(hwnd,SW_SHOW);UpdateWindow(hwnd);
 auto loader=LoadLibraryW((s->assets+L"\\WebView2Loader.dll").c_str());
 using CreateEnv=HRESULT(STDAPICALLTYPE*)(PCWSTR,PCWSTR,ICoreWebView2EnvironmentOptions*,ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler*);
 auto create=loader?reinterpret_cast<CreateEnv>(GetProcAddress(loader,"CreateCoreWebView2EnvironmentWithOptions")):nullptr;
 if(!create){s->emit("{\"event\":\"error\",\"message\":\"WebView2 loader unavailable\"}");return hwnd;}
 ComPtr<ICoreWebView2EnvironmentOptions> options;
#ifdef OMNICLOCK_UI_REVIEW
 // Test build only: the elevated test host ignores environment overrides.
 // Normal release artifacts cannot enable this fixed loopback endpoint.
 auto reviewOptions=Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
 reviewOptions->put_AdditionalBrowserArguments(L"--remote-debugging-port=9229 --remote-debugging-address=127.0.0.1");
 options=reviewOptions;
#endif
 create(nullptr,s->profile.c_str(),options.Get(),Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>([s](HRESULT error,ICoreWebView2Environment*env)->HRESULT{
  if(s->closed)return S_OK;if(FAILED(error)||!env){s->emit("{\"event\":\"error\",\"message\":\"WebView2 runtime unavailable\"}");return S_OK;}
  env->CreateCoreWebView2Controller(s->hwnd,Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>([s](HRESULT error,ICoreWebView2Controller*control)->HRESULT{
   if(s->closed)return S_OK;if(FAILED(error)||!control){s->emit("{\"event\":\"error\",\"message\":\"WebView2 could not create a view\"}");return S_OK;}
   s->controller=control;control->get_CoreWebView2(&s->web);resize(s);
   ComPtr<ICoreWebView2Controller2> color;if(SUCCEEDED(control->QueryInterface(IID_PPV_ARGS(&color))))color->put_DefaultBackgroundColor({0,0,0,0});
   ComPtr<ICoreWebView2Settings> settings;s->web->get_Settings(&settings);settings->put_AreDefaultContextMenusEnabled(FALSE);settings->put_AreDevToolsEnabled(FALSE);settings->put_IsStatusBarEnabled(FALSE);settings->put_IsScriptEnabled(TRUE);
   ComPtr<ICoreWebView2_3> mapping;if(SUCCEEDED(s->web.As(&mapping))){mapping->SetVirtualHostNameToFolderMapping(L"omniclock.local",s->assets.c_str(),COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS);auto parent=s->assets.substr(0,s->assets.find_last_of(L"/\\"));mapping->SetVirtualHostNameToFolderMapping(L"omniclock-assets.local",parent.c_str(),COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW);}
   EventRegistrationToken token{};
   s->web->add_WebMessageReceived(Callback<ICoreWebView2WebMessageReceivedEventHandler>([s](ICoreWebView2*,ICoreWebView2WebMessageReceivedEventArgs*args)->HRESULT{LPWSTR source=nullptr,json=nullptr;args->get_Source(&source);bool allowed=s->permits(source);CoTaskMemFree(source);if(allowed&&SUCCEEDED(args->get_WebMessageAsJson(&json))){auto msg=utf8(json);if(msg.size()<=(s->url.rfind("https://omniclock.local/",0)==0 ? 12*1024*1024 : 512*1024)){s->messages.push_back("{\"__pageMessage\":"+msg+"}");PostMessageW(s->hwnd,WM_APP+90,0,0);}CoTaskMemFree(json);}return S_OK;}).Get(),&token);
   s->web->add_NavigationStarting(Callback<ICoreWebView2NavigationStartingEventHandler>([s](ICoreWebView2*,ICoreWebView2NavigationStartingEventArgs*args)->HRESULT{LPWSTR uri=nullptr;args->get_Uri(&uri);if(!s->permits(uri))args->put_Cancel(TRUE);CoTaskMemFree(uri);return S_OK;}).Get(),&token);
   s->web->add_NewWindowRequested(Callback<ICoreWebView2NewWindowRequestedEventHandler>([](ICoreWebView2*,ICoreWebView2NewWindowRequestedEventArgs*args)->HRESULT{args->put_Handled(TRUE);return S_OK;}).Get(),&token);
   s->web->add_PermissionRequested(Callback<ICoreWebView2PermissionRequestedEventHandler>([](ICoreWebView2*,ICoreWebView2PermissionRequestedEventArgs*args)->HRESULT{args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);return S_OK;}).Get(),&token);
   s->web->add_NavigationCompleted(Callback<ICoreWebView2NavigationCompletedEventHandler>([s](ICoreWebView2*,ICoreWebView2NavigationCompletedEventArgs*args)->HRESULT{BOOL success=FALSE;args->get_IsSuccess(&success);if(success){s->ready=true;if(!s->pending.empty())s->web->PostWebMessageAsJson(wide(s->pending.c_str()).c_str());s->emit("{\"event\":\"ready\"}");}return S_OK;}).Get(),&token);
   if(s->script.empty())s->web->Navigate(wide(s->url.c_str()).c_str());
   else s->web->AddScriptToExecuteOnDocumentCreated(s->script.c_str(),Callback<ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler>([s](HRESULT,PCWSTR)->HRESULT{if(!s->closed)s->web->Navigate(wide(s->url.c_str()).c_str());return S_OK;}).Get());
   return S_OK;
  }).Get());return S_OK;
 }).Get());return hwnd;
}
void omni_web_send(void*window,const char*json){auto s=get((HWND)window);if(!s)return;s->pending=json?json:"{}";if(s->ready&&s->web)s->web->PostWebMessageAsJson(wide(s->pending.c_str()).c_str());}
void omni_web_script(void*window,const char*script){auto s=get((HWND)window);if(s&&s->web&&!s->closed)s->web->ExecuteScript(wide(script).c_str(),nullptr);}
void omni_web_opacity(void*window,double alpha){
 HWND h=(HWND)window;auto s=get(h);if(!s)return;alpha=std::max(.25,std::min(1.0,alpha));if(s->opacity==alpha)return;s->opacity=alpha;
 auto style=GetWindowLongPtrW(h,GWL_EXSTYLE);
 if(alpha<.999){SetWindowLongPtrW(h,GWL_EXSTYLE,style|WS_EX_LAYERED);win_fluent_apply(h,WIN_FLUENT_FALLBACK);SetLayeredWindowAttributes(h,0,(BYTE)(alpha*255+.5),LWA_ALPHA);}
 else {SetWindowLongPtrW(h,GWL_EXSTYLE,style&~WS_EX_LAYERED);win_fluent_apply(h,WIN_FLUENT_ACRYLIC);}
 RedrawWindow(h,nullptr,nullptr,RDW_INVALIDATE|RDW_ERASE|RDW_ALLCHILDREN);
}
void omni_web_show(void*window,int visible){HWND h=(HWND)window;if(!IsWindow(h))return;ShowWindow(h,visible?SW_SHOWNORMAL:SW_HIDE);if(visible)SetForegroundWindow(h);}
void omni_web_close(void*window){if(IsWindow((HWND)window))DestroyWindow((HWND)window);}
int omni_web_visible(void*window){return IsWindow((HWND)window)&&IsWindowVisible((HWND)window)&&!IsIconic((HWND)window);}
void omni_web_anchor(void*window,void*owner){
 RECT r{},w{};auto s=get((HWND)window);if(!s||!GetWindowRect((HWND)owner,&r)||!GetWindowRect((HWND)window,&w))return;
 MONITORINFO mi{sizeof(mi)};GetMonitorInfoW(MonitorFromWindow((HWND)owner,MONITOR_DEFAULTTONEAREST),&mi);
 int width=w.right-w.left,height=w.bottom-w.top;const int gap=8;
 width=std::min(width,(int)(mi.rcWork.right-mi.rcWork.left)-16);height=std::min(height,(int)(mi.rcWork.bottom-mi.rcWork.top)-16);
 int x=(r.left+r.right-width)/2,y=r.bottom+gap;
 if(s->key=="summary"){x=mi.rcWork.left+(mi.rcWork.right-mi.rcWork.left-width)/2;y=mi.rcWork.top+(mi.rcWork.bottom-mi.rcWork.top-height)/2;}
 else {
  int below=mi.rcWork.bottom-r.bottom-gap,above=r.top-mi.rcWork.top-gap;
  if(below>=320)height=std::min(height,below);
  else if(above>=320){height=std::min(height,above);y=r.top-height-gap;}
  else {x=r.right+gap;if(x+width>mi.rcWork.right)x=r.left-width-gap;y=(r.top+r.bottom-height)/2;}
 }
 x=std::max((int)mi.rcWork.left+8,std::min(x,(int)mi.rcWork.right-width-8));y=std::max((int)mi.rcWork.top+8,std::min(y,(int)mi.rcWork.bottom-height-8));
 SetWindowPos((HWND)window,HWND_TOP,x,y,width,height,SWP_NOACTIVATE);
}

int omni_web_capture(void*window,const char*path){auto s=get((HWND)window);if(!s||!s->web||!s->ready)return 0;ComPtr<IStream>stream;if(FAILED(SHCreateStreamOnFileEx(wide(path).c_str(),STGM_CREATE|STGM_READWRITE|STGM_SHARE_EXCLUSIVE,FILE_ATTRIBUTE_NORMAL,TRUE,nullptr,&stream)))return 0;return SUCCEEDED(s->web->CapturePreview(COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG,stream.Get(),Callback<ICoreWebView2CapturePreviewCompletedHandler>([stream](HRESULT)->HRESULT{return S_OK;}).Get()));}
