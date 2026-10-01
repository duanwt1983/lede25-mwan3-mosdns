# Authelia 与门户「账户与安全」

门户内改密调用 Authelia API（`/authelia/api/change-password` 等），需 Authelia **4.38+** 且未关闭用户改密。

在 `configuration.yml` 中确认：

- `server.address` 与 Nginx 反代路径一致（如 `tcp://127.0.0.1:9091/authelia/`）
- 文件用户后端可改密；LDAP 需 `authentication_backend.ldap.permit_change_password: true`
- 未设置 `password_change_disabled`（或设为 `false`）

若策略要求 **会话提升**，提交新密码前会向用户邮箱发送一次性验证码（与 Authelia 用户门户行为一致）。
