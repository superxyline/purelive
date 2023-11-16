import os
import shutil
import time
source_dir_name = 'E:/project/pure_live_release/'
target_apk_dir_name = 'E:/project/pure_live/build/windows/runner/Release/'
target_win_app_name = 'E:/project/pure_live/build/app/outputs/flutter-apk/'
files = []
apkDirArr = ['all', 'v7a', 'v8a', 'x86']
allowedFileArr = ['apk', 'msix']
windowsName = 'pure_live'
def traversal_dirs(path,version):
    for file in os.listdir(path):
        file_path = os.path.join(path, file)
        if os.path.isdir(file_path):
           type = file_path.split('/')[-1].split('-')[-1]
           isApk = type in apkDirArr
           if isApk:
              rename = version + '-' + type
              os.rename(file_path, os.path.join(path, rename))
           else:
              rename = 'windows-' + version
              os.rename(file_path, os.path.join(path, rename))
          
def traversal_files(path):
    for item in os.scandir(path):
        if item.is_file():
            fileName = item.path.split('/')[-1].split('\\')[-1]
            filePath = item.path.split('/')[-1].split('\\')[0]
            type = item.path.split('/')[-1].split('\\')[-1].split('.')[1]
            # 先删除zip文件
            if fileName.split('.')[-1] == "zip":
                os.remove(item.path)
            allowed = type in allowedFileArr
            # 复制apk
            if allowed:
              os.remove(item.path)
              src = target_apk_dir_name + fileName
              dst = source_dir_name + filePath
              if os.path.exists(src):
                  shutil.copy(src, dst)
              else:
                  # msix
                  src = target_win_app_name + fileName
                  shutil.copy(src, dst)
        else:
            traversal_files(item)
def zip_dirs(path):
    for file in os.listdir(path):
        file_path = os.path.join(path, file)
        if os.path.isdir(file_path):
           shutil.make_archive(file_path, 'zip', file_path)

def main():
        version = str(input("请输入你想发布的版本："))
        # 先改名字
        traversal_dirs(source_dir_name,version)
        # 复制文件
        traversal_files(source_dir_name)
        # 压缩为zip
        zip_dirs(source_dir_name)
        # 12
if __name__ == '__main__':
     main()