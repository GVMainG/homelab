import paramiko
import os
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

HOST = '192.168.1.51'
USER = 'user-home'
PASS = '9059'
LOCAL_DIR = r'C:\Users\GV\Desktop\homelab\vm-db-01'
REMOTE_DIR = '/root/homelab/vm-db-01'

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(HOST, username=USER, password=PASS, timeout=15)

def sudo(cmd: str, timeout: int = 60) -> str:
    full = f'echo {PASS} | sudo -S bash -c {repr(cmd)}'
    _, stdout, _ = client.exec_command(full, timeout=timeout, get_pty=True)
    out = stdout.read().decode('utf-8', errors='replace')
    print(out, end='')
    return out

print(f"==> Подключился к {HOST}")

# ── 1. Создаём директорию на VM ─────────────────────────────────────
print(f"\n==> Создаю {REMOTE_DIR} на VM...")
sudo(f'mkdir -p {REMOTE_DIR}')

# ── 2. Загружаем файлы по SFTP (под root через /tmp) ────────────────
# SFTP работает от user-home, поэтому грузим в /tmp, затем mv через sudo

print(f"\n==> Копирую файлы из {LOCAL_DIR}...")
sftp = client.open_sftp()

files_to_upload = [
    'deploy.sh',
    'backup.sh',
    'sync.sh',
    'docker-compose.yml',
    '.env.example',
]

for fname in files_to_upload:
    local_path = os.path.join(LOCAL_DIR, fname)
    if not os.path.exists(local_path):
        print(f"   [skip] {fname} -- not found locally")
        continue
    tmp_path = f'/tmp/{fname}'
    sftp.put(local_path, tmp_path)
    sudo(f'mv {tmp_path} {REMOTE_DIR}/{fname} && chmod +x {REMOTE_DIR}/{fname} 2>/dev/null || true')
    print(f"   [ok] {fname}")

sftp.close()

# ── 3. .env ─────────────────────────────────────────────────────────
print("\n==> Проверяю .env...")
out = sudo(f'test -f {REMOTE_DIR}/.env && echo ENV_EXISTS || echo ENV_MISSING')
if 'ENV_MISSING' in out:
    print("==> Копирую .env.example -> .env")
    sudo(f'cp {REMOTE_DIR}/.env.example {REMOTE_DIR}/.env')

# ── 4. Деплой ───────────────────────────────────────────────────────
print("\n==> Запускаю deploy.sh...")
sudo(f'cd {REMOTE_DIR} && bash deploy.sh 2>&1', timeout=180)

# ── 5. Статус ───────────────────────────────────────────────────────
print("\n==> Статус контейнеров:")
sudo(f'docker compose -f {REMOTE_DIR}/docker-compose.yml ps')

client.close()
print("\n==> Готово.")
