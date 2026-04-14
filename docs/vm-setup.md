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

| Ресурс | vm-db-02 | vm-proxy-02 |
|---|---|---|
| CPU | 2 vCPU | 1 vCPU |
| RAM | 2 GB | 1 GB |
| Disk | 20 GB | 10 GB |
| ОС | Ubuntu Server 22.04 LTS / Debian 12 | Ubuntu Server 22.04 LTS / Debian 12 |
| Сеть | LAN 192.168.1.0/24, static IP | LAN 192.168.1.0/24, static IP |

---

## vm-db-02 (192.168.1.52)

### 1. Создание VM в Proxmox

```bash
# На Proxmox хосте
qm create 102 --name vm-db-02 --memory 2048 --cores 2
qm importdisk 102 /path/to/ubuntu-22.04-live-server-amd64.iso local-lvm
qm set 102 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-102-disk-0
qm set 102 --net0 virtio,bridge=vmbr0
qm set 102 --boot order=scsi0
qm start 102
```

### 2. Установка ОС

- Загрузиться с ISO, установить Ubuntu Server
- Static IP: `192.168.1.52/24`, gateway `192.168.1.1`, DNS `192.168.1.51` (proxy VM)
- Пользователь: `gv` (или другой), настроить SSH ключ

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
git sparse-checkout set vm-db-02
```

**ИЛИ** использовать `sync.sh`:
```bash
cd /opt/homelab/vm-db-02
sudo bash sync.sh
```

### 5. Настройка .env

```bash
cd /opt/homelab/vm-db-02
cp .env.example .env
nano .env
# Заменить все CHANGE_ME на реальные значения
```

### 6. Запуск сервисов

```bash
cd /opt/homelab/vm-db-02
docker compose up -d --remove-orphans
docker compose ps    # проверить что все healthy
```

---

## vm-proxy-02 (192.168.1.51)

### 1. Создание VM в Proxmox

```bash
qm create 101 --name vm-proxy-02 --memory 1024 --cores 1
qm importdisk 101 /path/to/ubuntu-22.04-live-server-amd64.iso local-lvm
qm set 101 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-101-disk-0
qm set 101 --net0 virtio,bridge=vmbr0
qm set 101 --boot order=scsi0
qm start 101
```

### 2. Установка ОС

- Static IP: `192.168.1.51/24`, gateway `192.168.1.1`, DNS `8.8.8.8` (внешний, до настройки dnsmasq)

### 3. Базовая настройка ОС

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose-plugin git curl
sudo systemctl enable docker
sudo usermod -aG docker $USER
sudo timedatectl set-timezone Europe/Moscow
```

### 4. Установка dnsmasq

```bash
# Временный DNS
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf

# Остановить systemd-resolved
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved

# Установить dnsmasq
sudo apt install -y dnsmasq

# Настроить split-DNS
sudo nano /etc/dnsmasq.d/01-split-dns.conf
# Добавить:
#   address=/home.loc/192.168.1.51
#   listen-address=127.0.0.1,192.168.1.51

sudo systemctl enable dnsmasq
sudo systemctl start dnsmasq

# Обновить resolv.conf
echo "nameserver 192.168.1.51" | sudo tee /etc/resolv.conf
```

### 5. Настройка git sparse checkout

```bash
cd /opt
sudo mkdir -p homelab && sudo chown $USER:$USER homelab
cd homelab

git clone --filter=blob:none --sparse --branch main https://github.com/GVMainG/homelab.git .
git sparse-checkout set vm-proxy-02
```

### 6. Настройка .env и запуск NPM

```bash
cd /opt/homelab/vm-proxy-02
cp .env.example .env
nano .env   # задать NPM_ADMIN_EMAIL и NPM_ADMIN_PASSWORD

docker compose up -d --remove-orphans
docker compose ps
```

Admin UI доступен на `http://192.168.1.51:81`.

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
