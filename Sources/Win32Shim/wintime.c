#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "include/winshim.h"

typedef int32_t (__cdecl *map_windows_zone)(const wchar_t *,int32_t,const char *,wchar_t *,int32_t,int32_t *);
int win_system_timezone_offset(void) {
    DYNAMIC_TIME_ZONE_INFORMATION zone={0};DWORD state=GetDynamicTimeZoneInformation(&zone);
    if(state==TIME_ZONE_ID_INVALID)return 0;
    return -(zone.Bias+(state==TIME_ZONE_ID_DAYLIGHT?zone.DaylightBias:zone.StandardBias))*60;
}
int win_system_timezone(char *output,int capacity) {
    if(!output||capacity<32)return 0;output[0]=0;
    DYNAMIC_TIME_ZONE_INFORMATION zone={0};DWORD state=GetDynamicTimeZoneInformation(&zone);
    if(state==TIME_ZONE_ID_INVALID)return 0;
    HMODULE icu=LoadLibraryExW(L"icu.dll",NULL,LOAD_LIBRARY_SEARCH_SYSTEM32);
    if(icu && !zone.DynamicDaylightTimeDisabled){
        map_windows_zone map=(map_windows_zone)(void*)GetProcAddress(icu,"ucal_getTimeZoneIDForWindowsID");
        if(map){wchar_t name[128]={0};int32_t status=0;int32_t count=map(zone.TimeZoneKeyName,-1,NULL,name,128,&status);
            if(status<=0&&count>0&&count<128)WideCharToMultiByte(CP_UTF8,0,name,-1,output,capacity,NULL,NULL);}
    }
    if(icu)FreeLibrary(icu);
    if(output[0])return 1;
    int minutes=win_system_timezone_offset()/60,absolute=minutes<0?-minutes:minutes;
    snprintf(output,(size_t)capacity,"GMT%c%02d:%02d",minutes<0?'-':'+',absolute/60,absolute%60);
    return 1;
}
void win_set_process_timezone(const char *name) {
    /* Application process only; do not change the Windows time zone or clock. */
    if(name&&*name){_putenv_s("TZ",name);SetEnvironmentVariableA("TZ",name);}
}
