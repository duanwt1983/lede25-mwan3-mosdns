# Authelia 与门户「账户与安全」

门户内改密经 `center-portal-admin`：**4.39+** 用 Authelia `POST /api/change-password`；**4.38.x 无改密 API**，在 **file 用户后端** 下由 admin 校验当前密码并更新 `users_database.yml`（需已登录会话）。

需 Authelia **4.38+** 且未关闭用户改密。

在 `configuration.yml` 中确认：

- `server.address` 与 Nginx 反代路径一致（如 `tcp://127.0.0.1:9091/authelia/`）
- 文件用户后端可改密；LDAP 需 `authentication_backend.ldap.permit_change_password: true`
- 未设置 `password_change_disabled`（或设为 `false`）

若策略要求 **会话提升**，会先触发一次性验证码。当前 6.251 使用 **filesystem notifier**（写入 `/var/lib/authelia/notification.txt`），门户会提示 SSH 查看；生产环境建议配置 **SMTP** 发到用户邮箱。
