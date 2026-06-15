# 散场记

散场记是一款给影迷朋友的私人电子票夹。它适合散场后收好一张电影票，也适合开场前先记下即将开始的这一场：把纸质票根或电子票截图保存下来，连同影院、座位、时间和一点当时的心情一起留住。

## 核心能力

- 票根采集：支持拍摄实体票根，或从相册导入实体票照片、电子票截图
- 票面识别：先用 Apple Vision 在设备端提取文本和坐标，再把“文字+物理位置”的纯文本交给大模型校对和结构化
- 信息校对：观影信息可由用户修正；影片资料只要有片名就会自动补全，不允许靠用户手填缺失资料
- 电影资料补全：优先通过豆瓣资料代理获取上映日期、导演、片长、豆瓣评分和海报，TMDB 作为兜底资料源
- 本地资料库：使用 SwiftData 保存观影记录，单张票根图片和海报缓存保存在本机
- 私人票夹体验：提供票夹式首页、票根详情、搜索、编辑和删除能力

## 当前版本

- 平台：原生 iOS App，优先适配 iPhone
- 目标：当前按未来上架 App Store 的方向组织产品范围、隐私策略和工程结构
- 数据策略：每条观影记录暂时只保存一张票根图片，并默认尝试缓存一张电影海报
- 资料来源：电影资料优先来自豆瓣资料代理，TMDB 作为兜底；正式保存前会检查片名、上映日期、导演、片长、豆瓣评分是否齐全
- 个人记录：评分和短评为非必填字段，当前版本不扩展成复杂影评功能
- 隐私策略：票根图片保存在本机；启用大模型后也只发送 Vision 识别出的文本、坐标和置信度，不上传票根图片
- 备份策略：暂不建设自有账号和云服务，后续优先考虑 iCloud 备份
- 产品边界：当前版本聚焦私人票根管理，不包含社交分享、公开主页或豆瓣影评同步

## 配置

电影资料优先来自豆瓣资料代理，TMDB 作为兜底。由于豆瓣没有稳定公开电影 API，且网页搜索路径有反爬限制，App 不直接抓取豆瓣网页；请把豆瓣抓取、缓存、限频和合规控制放在自己的服务端或代理层。

本地配置方式：

1. 复制 `Local.xcconfig.example` 为 `Local.xcconfig`
2. 在 `Local.xcconfig` 中优先填入 `DOUBAN_API_BASE_URL`
3. 可选填入 `DOUBAN_API_KEY`、`TMDB_API_KEY`
4. 重新运行 Xcode

`Local.xcconfig` 已加入忽略列表，不要将真实密钥提交到仓库。正式发布前建议改为通过后端代理注入 API Key。

豆瓣代理接口约定：

```text
GET {DOUBAN_API_BASE_URL}/movie/search?query=片名
Authorization: Bearer {DOUBAN_API_KEY} // 可选
```

响应可以是单个影片对象，也可以是 `{ "results": [...] }`。推荐字段：

```json
{
  "title": "非穷尽列举",
  "original_title": "Inter Alia",
  "release_date": "2025-09-04",
  "directors": ["Justin Martin"],
  "runtime_minutes": 105,
  "douban_rating": "8.2",
  "poster_url": "https://..."
}
```

正式保存时，影片信息必须包含片名、上映日期、导演、片长和豆瓣评分。观影时间、影院、影厅、座位、票价属于观影信息，缺失时允许用户补。

Cloudflare Worker 参考实现见 `server/cloudflare-worker/douban-metadata-proxy.js`。它包含鉴权、KV 缓存、基础限频和封禁状态保护；生产环境建议优先使用授权数据源或预热缓存，避免高频抓取豆瓣页面。

如果要试用大模型票根识别，在同一个 `Local.xcconfig` 中填入：

```xcconfig
LLM_API_KEY = your_llm_api_key_here
LLM_API_BASE_URL =
LLM_API_STYLE = responses
LLM_MODEL = gpt-5-mini
```

启用后，每次导入票根都会先在本机用 Vision OCR 提取文本块、坐标和置信度，再把这段纯文本发送到 OpenAI Responses API 做空间关系推理、纠错和结构化。票根图片不会上传。

切换到其他兼容 OpenAI Chat Completions 的模型服务时，只需要改配置，例如：

```xcconfig
LLM_API_KEY = your_provider_api_key
URL_SLASH = /
LLM_API_BASE_URL = https:$(URL_SLASH)$(URL_SLASH)api.deepseek.com$(URL_SLASH)v1
LLM_API_STYLE = chat_completions
LLM_MODEL = deepseek-v4-flash
```

常见兼容服务通常使用 `chat_completions`；官方 OpenAI 推荐保留 `responses`。注意：`xcconfig` 会把裸写的 `//` 识别成注释，所以 URL 要用 `$(URL_SLASH)` 拼出来。

## 技术栈

- SwiftUI
- SwiftData
- Vision
- OpenAI Responses API
- PhotosUI
- TMDB API

## 识别测试集

`tests/fixtures/ticket_recognition_cases.json` 提供了一组小型合成票根 OCR 回归样本，覆盖平台订单、售票时间干扰、多金额、左右联混排、字段分行、英文标签、繁体、褪色错字、推荐内容、缺字段和人工复核等场景。

可以用下面的脚本对比一次识别方案输出：

```bash
python3 tests/evaluate_ticket_recognition.py tests/fixtures/ticket_recognition_cases.json path/to/predictions.json
```
