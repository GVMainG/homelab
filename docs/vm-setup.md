# Настройка виртуальных машин

## Для чего этот документ и как вести?

Этот документ описывает процесс создания и первоначальной настройки каждой виртуальной машины в homelab. Он нужен, чтобы можно было воспроизвести развёртывание VM с нуля — например, после сбоя или при масштабировании.

**Что должно быть в этом документе:**

- Минимальные требования к ресурсам для каждой VM (CPU, RAM, disk)
- Версия и образ ОС, используемый для VM
- Пошаговая инструкция установки ОС на Proxmox
- Базовая настройка ОС: пользователь, SSH, сеть, таймзона, обновления
- Установка зависимостей: Docker, Docker Compose, git, curl и др.
- Настройка sparse checkout для работы с репозиторием homelab
- Скриншоты или команды Proxmox (qm create, qm snapshot и т.д.)
- Список файлов конфигурации, которые создаются в процессе

**Правила документирования:**

- Все команды должны быть копи-паст готовыми (полные пути, без пропусков)
- Указывать версии ПО, которые были проверены и работают
- Разделять инструкции по VM — каждая VM в своём подразделе
- Отмечать шаги, требующие ручного вмешательства
- Если шаг зависит от Proxmox-конфигурации — давать ссылку на соответствующий раздел
- Команды Proxmox оформлять в отдельных блоках с пояснением параметров
- Обновлять при изменении требований к ресурсам или версии ОС

---

## Минимальные требования к VM

| Ресурс | vm-db-01 | vm-DevOps-01 | vm-apps-01 |
| --- | --- | --- | --- |
| CPU | 2 vCPU | 1 vCPU | 1 vCPU |
| RAM | 2 GB | 1 GB | 512 MB–1 GB |
| Disk | 20 GB | 10 GB | 20 GB+ (для загрузок видео) |
| ОС | Debian 12 | Debian 12 | Debian 12 |
| Сеть | LAN 192.168.1.0/24, static IP | LAN 192.168.1.0/24, static IP | LAN 192.168.1.0/24, static IP |

---

## vm-db-01 (192.168.1.36)

### 1. Создание VM в Proxmox

```bash
# На Proxmox хосте
qm create 101 --name vm-db-01 --memory 2048 --cores 2
qm importdisk 101 /path/to/ubuntu-22.04-live-server-amd64.iso local-lvm
qm set 101 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-101-disk-0
qm set 101 --net0 virtio,bridge=vmbr0
qm set 101 --boot order=scsi0
qm start 101
```

### 2. Установка ОС

- Загрузиться с ISO, установить Ubuntu Server
- Static IP: `192.168.1.36/24`, gateway `192.168.1.1`, DNS `8.8.8.8`
- Пользователь: `user-home`, настроить SSH ключ

### 3. Базовая настройка ОС

```bash
# Обновления
sudo apt update && sudo apt upgrade -y

# Установка зависимостей
sudo apt install -y docker.io docker-compose-plugin git curl

# Включить Docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# Таймзона
sudo timedatectl set-timezone Europe/Moscow

# SSH ключ (если не настроен при установке)
mkdir -p ~/.ssh
chmod 700 ~/.ssh
# Скопировать публичный ключ в ~/.ssh/authorized_keys
```

### 4. Настройка git sparse checkout

```bash
cd /opt
sudo mkdir -p homelab && sudo chown $USER:$USER homelab
cd homelab

git clone --filter=blob:none --sparse --branch main https://github.com/GVMainG/homelab.git .
git sparse-checkout set vm-db-01
```

**ИЛИ** использовать `sync.sh`:
```bash
cd /opt/homelab/vm-db-01
sudo bash sync.sh
```

### 5. Настройка .env

```bash
cd /opt/homelab/vm-db-01
cp .env.example .env
nano .env
# Заменить все CHANGE_ME на реальные значения
```

### 6. Запуск сервисов

```bash
cd /opt/homelab/vm-db-01
docker compose up -d --remove-orphans
docker compose ps    # проверить что все healthy
```

---

## vm-DevOps-01 (192.168.1.XX)

### Создание VM в Proxmox (vm-DevOps-01)

```bash
# На Proxmox хосте
qm create 102 --name vm-devops-01 --memory 1024 --cores 1
qm importdisk 102 /path/to/debian-12-generic-amd64.iso local-lvm
qm set 102 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-102-disk-0
qm set 102 --net0 virtio,bridge=vmbr0
qm set 102 --boot order=scsi0
qm start 102
```

### Установка ОС (vm-DevOps-01)

- Загрузиться с ISO, установить Debian 12
- Static IP: `192.168.1.XX/24`, gateway `192.168.1.1`, DNS `8.8.8.8`
- Пользователь: `user-home`, настроить SSH ключ

### Первичный деплой (vm-DevOps-01)

Bootstrap одной командой от root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/GVMainG/homelab/main/vm-DevOps-01/first-deployment.sh)
```

Скрипт: клонирует репо, ставит Docker, генерирует `.env` (ENCRYPTION_KEY), запускает Dockhand.

### После деплоя (vm-DevOps-01)

```bash
# Настроить FRP-туннель (Dockhand :3000 → VPS :13000)
sudo bash /opt/homelab/vm-DevOps-01/frp-setup.sh

# Открыть Dockhand UI
# http://192.168.1.XX:3000
# Settings → Authentication → включить аутентификацию
```

---

## vm-apps-01 (192.168.1.YY)

### Создание VM в Proxmox (vm-apps-01)

```bash
# На Proxmox хосте
qm create 103 --name vm-apps-01 --memory 1024 --cores 1
qm importdisk 103 /path/to/debian-12-generic-amd64.iso local-lvm
qm set 103 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-103-disk-0
qm set 103 --net0 virtio,bridge=vmbr0
qm set 103 --boot order=scsi0
qm start 103
```

### Установка ОС (vm-apps-01)

- Загрузиться с ISO, установить Debian 12
- Static IP: `192.168.1.YY/24`, gateway `192.168.1.1`, DNS `8.8.8.8`
- Пользователь: `user-home`, настроить SSH ключ

### Базовая настройка ОС (vm-apps-01)

```bash
# Обновления
sudo apt update && sudo apt upgrade -y

# Установка зависимостей
sudo apt install -y docker.io docker-compose-plugin git curl

# Включить Docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# Таймзона
sudo timedatectl set-timezone Europe/Moscow
```

### Настройка git sparse checkout (vm-apps-01)

```bash
cd /opt
sudo mkdir -p homelab && sudo chown $USER:$USER homelab
cd homelab

git clone --filter=blob:none --sparse --branch main https://github.com/GVMainG/homelab.git .
git sparse-checkout set vm-apps-01
```

**ИЛИ** использовать `sync.sh`:
```bash
cd /opt/homelab/vm-apps-01
bash sync.sh
```

### Развёртывание MeTube (vm-apps-01)

```bash
cd /opt/homelab/vm-apps-01
cp .env.example .env
nano .env
# Отредактировать параметры YTDL_FORMAT, YTDL_EXTRACT_AUDIO_FORMAT и т.д. (опционально)
```

Запуск сервиса:

```bash
cd /opt/homelab/vm-apps-01
docker compose up -d --remove-orphans
docker compose ps    # проверить что healthy
```

Доступ: `http://192.168.1.YY:8081`

---

## Снапшоты Proxmox

Перед любыми изменениями:

```bash
# Snapshot перед обновлением
qm snapshot <vmid> $(date +%Y%m%d)-before-update

# Список снапшотов
qm listsnapshot <vmid>

# Rollback
qm rollback <vmid> <snapname>
```
