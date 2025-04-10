#!/bin/bash

# 确保LaunchScreen.imageset目录存在
mkdir -p ReadAloud/Assets.xcassets/LaunchScreen.imageset

# 假设您已将启动图片保存为launch_image.png
# 复制图片到对应目录并重命名为不同分辨率版本
cp launch_image.png ReadAloud/Assets.xcassets/LaunchScreen.imageset/LaunchScreen.png
cp launch_image.png ReadAloud/Assets.xcassets/LaunchScreen.imageset/LaunchScreen@2x.png
cp launch_image.png ReadAloud/Assets.xcassets/LaunchScreen.imageset/LaunchScreen@3x.png

# 更新Contents.json文件
cat > ReadAloud/Assets.xcassets/LaunchScreen.imageset/Contents.json << EOF
{
  "images" : [
    {
      "filename" : "LaunchScreen.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "LaunchScreen@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "LaunchScreen@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "启动图片已添加到项目中" 