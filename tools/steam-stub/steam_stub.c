#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>

BOOL isAnyProcessRunning(const char *processes[], int count) {
    PROCESSENTRY32 pe;
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap == INVALID_HANDLE_VALUE)
        return FALSE;

    pe.dwSize = sizeof(PROCESSENTRY32);
    if (!Process32First(hSnap, &pe)) {
        CloseHandle(hSnap);
        return FALSE;
    }

    do {
        for (int i = 0; i < count; i++) {
            if (_stricmp(pe.szExeFile, processes[i]) == 0) {
                CloseHandle(hSnap);
                return TRUE;
            }
        }
    } while (Process32Next(hSnap, &pe));

    CloseHandle(hSnap);
    return FALSE;
}

void launchGame() {
    STARTUPINFO si = {0};
    PROCESS_INFORMATION pi = {0};
    si.cb = sizeof(si);

    char path[MAX_PATH];
    DWORD len = GetEnvironmentVariableA("RAGNAROK_PATH", path, MAX_PATH);

    if (len == 0 || len >= MAX_PATH) {
        // fallback
        strcpy(path, "C:\\Gravity\\Ragnarok\\Ragnarok.exe");
    }

    if (!CreateProcessA(
            path, NULL, NULL, NULL, FALSE,
            CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        DWORD err = GetLastError();
        char buffer[256];
        snprintf(buffer, sizeof(buffer), "Failed to start %s (error %lu)", path, err);
        OutputDebugStringA(buffer);
    } else {
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
    }
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    HANDLE hMutex = CreateMutexA(NULL, TRUE, "Global\\SteamDummyMonitor");

    BOOL alreadyRunning = (GetLastError() == ERROR_ALREADY_EXISTS);

    launchGame();

    if (alreadyRunning) {
        return 0;
    }

    const char *watchList[] = {
        "Ragexe.exe",
        "Ragnarok.exe",
        "Setup.exe"
    };

    while (isAnyProcessRunning(watchList, 3)) {
        Sleep(2000);
    }

    CloseHandle(hMutex);
    return 0;
}