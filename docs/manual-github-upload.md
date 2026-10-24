# 用GitHub网页手动上传

本文不需要令牌、不需要给浏览器额外的本地文件权限，也不要求安装Git。你自己在文件选择或拖放界面选择文件即可。

## 1. 选择私有仓库

已经建好仓库就打开它；还没有时，登录GitHub，点右上角“+ → New repository”，名称可用`dst-ai-companion`，可见性选**Private**，创建即可。已有同名README没关系，上传时可用新文件替换。

只上传本次准备的**纯源码目录**，或把本次源码ZIP解压后再选择里面的内容。不要从安装后的运行目录、旧开发仓库或上级目录拖文件。GitHub网页不会读取`.gitignore`来替你过滤拖进去的文件。

## 2. 上传源码，保持文件夹结构

1. 在仓库根目录点 **Add file → Upload files**。空仓库也可点“uploading an existing file”。
2. 从纯源码目录把文件夹和根文件拖进页面。**选择目录里面的内容，别把外层`dst-ai-companion-…`文件夹一起套进仓库。**
3. 确认预览有`README.md`、`package.json`、`bridge/server.mjs`、`mod/modmain.lua`等。若只剩文件名且丢了`bridge/`／`mod/`层级，请取消并重新按文件夹拖入。
4. 提交说明填写`Add standalone companion 0.8.0`，点 **Commit changes**。

GitHub网页目前每次最多100个文件，每个文件最多25 MiB；本项目所有源码文件都很小，但总数可能超过100。分两批最容易：

- 第一批：根目录文件＋`bridge/`＋`mod/`＋`tools/`。
- 第二批：`docs/`＋`test/`。

每批都从**仓库根目录**进入Upload files。不要把第二批放进某个已有子目录，避免产生`docs/docs/`等错误层级。网页上的“choose your files”适合根文件；整个文件夹建议拖放，才能保留结构。Windows资源管理器可在“查看 → 显示 → 隐藏的项目”中显示`.gitignore`和`.gitattributes`。

**不要只把源码ZIP上传到仓库根目录。** GitHub不会自动解压它，README和源码也不会因此显示出来。若还想提供“一份ZIP直接下载”，可额外创建一个Release，在Assets上传本次干净ZIP；源码仍按上述步骤上传。Release本身不是必须的，仓库的Code → Download ZIP也能下载源码。

## 3. 上传后检查

- 仓库根目录直接展示中文README，并能打开文中的相对链接。
- 有`bridge/`、`mod/`、`tools/`、`test/`、`docs/`和`package.json`。
- 没有`.git/`、`node_modules/`、`state/`、`reference/`、`backups/`、私人`role.md`、`config.json`或`ai_private.lua`。`config.example.json`和`role.example.md`是通用示例，可以保留。
- 用Code → Download ZIP重新下载一份，解压后看README和目录结构；首次使用者按README安装，不需要你的账号、登录文件或运行数据。

私有仓库不会自动给所有朋友开放：进入 **Settings → Collaborators／Manage access → Add people**，用朋友的GitHub用户名邀请；对方接受后才能访问。不要把模型登录或QQ账号共享给朋友。

## 4. 以后更新

仍在干净目录整理，再使用Add file → Upload files替换相应源码。网页上传不会自动删除已经过时的旧文件；若升级说明要求删除文件，请在GitHub网页逐项删除。运行数据、认证和私人角色始终不上传。

GitHub官方说明：[向仓库添加文件](https://docs.github.com/en/repositories/working-with-files/managing-files/adding-a-file-to-a-repository)。菜单和上传限制可能调整，以当时网页为准。
