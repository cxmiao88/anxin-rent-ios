# 安心租房 iOS 未签名 IPA 构建仓库

本仓库只用于在 GitHub Actions 的 macOS 运行器上编译「安心租房」iOS 原生壳，产出**未签名 IPA**。

- 应用形态：SwiftUI + WKWebView 壳，加载线上 H5 `https://cc.scxjydz.com/h5/`
- Bundle ID：`com.anxinhuiju.zufang`
- 版本：1.0.7 / 107
- 产物：`AnxinRent.ipa`（无签名），随 Release `v1.0.7` 发布
- 源工程在本地：`D:\安心租房项目\ios-shell`

## 说明

未签名 IPA 不能直接装到 iPhone，需要用爱思助手 / Sideloadly 等工具以免费 Apple ID 重签名后安装（证书 7 天有效）。
