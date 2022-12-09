#include <iostream>
#include <fstream>
#include <windows.h>
using namespace std;
#pragma comment(linker, "/subsystem:\"windows\" /entry:\"mainCRTStartup\"")

void getExePath(std::string &exeDir, std::string &exeName)
{
    char exeFullPath[MAX_PATH]; // Full path
    std::string strPath = "";

    GetModuleFileName(NULL,exeFullPath,MAX_PATH); //获取带有可执行文件名路径
    strPath=(std::string)exeFullPath;
    int pos = strPath.find_last_of('\\', strPath.length());
    exeDir = strPath.substr(0, pos);
    exeName = strPath.substr(pos + 1, strPath.length() - (pos + 1) - 4);
    return;
} 

int main(int argc, char **argv)
{
    std::string exeDir, exeName;
    getExePath(exeDir, exeName);
    ofstream outFile;
    outFile.open(exeDir + "\\" + exeName + ".cb"); //打开文件
    for (size_t i = 1; i < argc; i++)
    {
        outFile << argv[i]; //写入操作
    }
    outFile.close(); //关闭文件
    return 0;
}
