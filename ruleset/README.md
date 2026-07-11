# 本目录是 Mihomo 本地 rule-providers 规则。

部署脚本会把这些文件上传到路由器：

```text
/data/clash/ruleset/
```

当前模板：

- `private.yaml`：内网/保留地址直连
- `direct.yaml`：大陆和常用本地服务直连
- `proxy.yaml`：常见代理站点
- `ai.yaml`：AI 服务分流到 `AI` 策略组
- `reject.yaml`：基础广告/跟踪拒绝示例

这些只是“傻瓜默认规则”，后续你可以替换成自己的规则集。
