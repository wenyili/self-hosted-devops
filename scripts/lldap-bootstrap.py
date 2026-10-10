#!/usr/bin/env python3
"""lldap 初始化（lldap 起来之后运行一次，可重复运行）：
  1) 创建 Authelia 用的只读绑定账号 `authelia`（加入 lldap_strict_readonly 组），密码取自 secrets/authelia_ldap_password.txt
  2) 若给了 --seed 文件，按其中的分组/用户创建（不设置用户密码，密码请在管理界面里由本人设置）
用法： lldap-bootstrap.py [--seed seed.yml]
seed.yml 格式：
  groups: [组名, ...]
  users:
    用户名: {email: a@b.c, displayname: 显示名, groups: [组名, ...]}
管理员密码从 secrets/lldap_admin_password.txt 读取，不会打印。
"""
import json, os, subprocess, sys, urllib.request
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = "http://127.0.0.1:17170"
read = lambda n: open(os.path.join(ROOT, "secrets", n)).read().strip()


def post(path, body, token=None):
    req = urllib.request.Request(BASE + path, json.dumps(body).encode(), {"Content-Type": "application/json"})
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code} {path}: {e.read().decode()[:300]}")


def gql(token, query, variables=None):
    r = post("/api/graphql", {"query": query, "variables": variables or {}}, token)
    if r.get("errors"):
        raise RuntimeError(r["errors"][0]["message"])
    return r["data"]


def main():
    token = post("/auth/simple/login", {"username": "admin", "password": read("lldap_admin_password.txt")})["token"]
    groups = {g["displayName"]: g["id"] for g in gql(token, "{groups{id displayName}}")["groups"]}
    users = {u["id"] for u in gql(token, "{users{id}}")["users"]}

    def ensure_group(name):
        if name not in groups:
            groups[name] = gql(token, "mutation($n:String!){createGroup(name:$n){id displayName}}", {"n": name})["createGroup"]["id"]
            print(f"  创建分组 {name}")

    def ensure_user(uid, email, display):
        if uid not in users:
            gql(token, "mutation($u:CreateUserInput!){createUser(user:$u){id}}",
                {"u": {"id": uid, "email": email, "displayName": display}})
            users.add(uid)
            print(f"  创建用户 {uid}")

    def join(uid, group):
        ensure_group(group)
        try:
            gql(token, "mutation($u:String!,$g:Int!){addUserToGroup(userId:$u,groupId:$g){ok}}", {"u": uid, "g": groups[group]})
            print(f"  {uid} 加入 {group}")
        except RuntimeError as e:
            if "already" not in str(e).lower() and "duplicate" not in str(e).lower() and "unique" not in str(e).lower():
                raise

    # 1) Authelia 的只读绑定账号
    if "authelia" not in users:
        ensure_user("authelia", "authelia@localhost", "Authelia")
        subprocess.run(["docker", "exec", "-e", "LLDAP_USER_PASSWORD=" + read("authelia_ldap_password.txt"), "lldap",
                        "/app/lldap_set_password", "--base-url", "http://localhost:17170", "--token", token,
                        "--username", "authelia"], check=True)
        print("  已设置 authelia 绑定账号的密码")
    join("authelia", "lldap_strict_readonly")

    # 2) 可选种子
    if "--seed" in sys.argv:
        seed = yaml.safe_load(open(sys.argv[sys.argv.index("--seed") + 1])) or {}
        for g in seed.get("groups", []):
            ensure_group(g)
        for uid, u in (seed.get("users") or {}).items():
            try:
                ensure_user(uid, u["email"], u.get("displayname", uid))
                for g in u.get("groups", []):
                    join(uid, g)
            except RuntimeError as e:   # 例如 lldap 不接受某些用户名字符；不中断其它用户
                print(f"  ✘ 用户 {uid} 创建/加组失败: {e}", file=sys.stderr)
    print("完成")


if __name__ == "__main__":
    main()
