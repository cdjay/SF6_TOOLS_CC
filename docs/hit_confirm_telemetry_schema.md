# 确认训练统计 JSON 契约

确认训练只向本地追加匿名 JSONL 事件，不进行网络请求，也不读取或保存用户 Token。托盘负责登录身份、Token、上传重试、成功确认与队列消费。自由选择的训练项按“角色 + 前置 Action ID + 后续 Action ID”形成稳定的 `case_id`，网站可按 `case_id + revision` 聚合展示。

## 本地队列

`data/SF6_TrainingRemoteControl_data/HitConfirmTelemetry/events.jsonl`

该目录属于运行时状态，已被 Git 忽略，不进入发布源码清单。每行是一个完整 JSON 对象，采用追加写入，托盘应以 `event_id` 做幂等去重。

## 尝试事件

Schema：`sf6cc.hit_confirm_attempt.v1`

核心字段：

- `event_id`、`occurred_at`、`session_id`、`attempt_sequence`
- `case.case_id`、`case.revision`、角色、用户选择的前置与后续动作
- `runtime.sf6cc_version`、`runtime.control_mode`
- `opponent.strategy`
- `result.stimulus`：`hit` 或 `block`
- `result.decision`：`followup` 或 `hold`
- `result.correct`、`result.failure_code`
- `result.decision_frames`、后续动作 ID/指令

失败码当前包括：

- `missed_confirm`：命中后没有出允许的后续动作
- `blocked_misconfirm`：被防后仍出了后续动作
- `followup_did_not_combo`：出了后续动作，但没有形成目标连段

## 会话事件

Schema：`sf6cc.hit_confirm_session.v1`

会话事件记录完成原因、目标训练量、总正确率、命中确认率、被防收手率、三类错误计数、所选后续的使用次数，以及成功命中确认的平均/最快/最慢反应帧。

## 托盘与网站边界

托盘上传时可以在 HTTP 层关联当前登录用户，但不得回写 Token 到 Lua 队列。网站应保存原始 `event_id` 并保证重复上传不会重复计数。Lua 与 SF6CM/网站之间仅共享此 JSON 契约，不建立代码依赖。
