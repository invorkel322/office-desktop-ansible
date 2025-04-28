#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для обработки ошибок с повторами
safe_exec() {
    local cmd="$@"
    local max_retries=3
    local delay=5
    local retry_count=0
    local exit_code=0

    while [ $retry_count -lt $max_retries ]; do
        eval "$cmd"
        exit_code=$?
        if [ $exit_code -eq 0 ]; then
            return 0
        fi
        echo -e "${YELLOW}[ПОВТОР]${NC} Попытка $((retry_count+1)) из $max_retries: $cmd"
        sleep $delay
        ((retry_count++))
    done

    echo -e "${RED}[ОШИБКА]${NC} Не удалось выполнить: $cmd"
    return $exit_code
}

# Проверка root-прав
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[Ошибка]${NC} Этот скрипт должен быть запущен от имени ${GREEN}root${NC}."
    exit 1
fi

# Настройка обработки прерываний
trap 'echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ]${NC} Скрипт прерван. Проверьте текущее состояние системы."; exit 1' INT TERM

echo -e "${GREEN}==> Отключение SSH авторизации по паролю и настройка стабильного соединения...${NC}"

# Создаем резервную копию конфига SSH
safe_exec "cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak"

# Применяем настройки SSH с повторами при ошибках
safe_exec "sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
safe_exec "sed -i 's/^#ClientAliveInterval.*/ClientAliveInterval 60/' /etc/ssh/sshd_config"
safe_exec "sed -i 's/^#ClientAliveCountMax.*/ClientAliveCountMax 100/' /etc/ssh/sshd_config"

# Проверка конфигурации перед перезагрузкой
if ! sshd -t; then
    safe_exec "mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config"
    echo -e "${RED}[ОШИБКА]${NC} Неверная конфигурация SSH. Откат изменений."
    exit 1
fi

safe_exec "systemctl reload sshd"
echo -e "${GREEN}✅ Настройки SSH обновлены!${NC}"

echo -e "${GREEN}==> Создание пользователя devops...${NC}"

# Создание пользователя (без изменений)
safe_exec "useradd -m devops"
safe_exec "echo 'devops:devops_password' | chpasswd"
safe_exec "echo 'devops ALL=(ALL) NOPASSWD: ALL' | tee -a /etc/sudoers > /dev/null"
safe_exec "usermod -aG sudo devops"
echo -e "${GREEN}✅ Пользователь devops успешно создан!${NC}"

echo -e "${GREEN}==> Введите публичный SSH ключ:${NC}"
read -p "Введите публичный SSH ключ: " pubkey

# Проверка ввода ключа
if [[ -z "$pubkey" ]]; then
    echo -e "${RED}[ОШИБКА]${NC} Не введен SSH ключ."
    exit 1
fi

# Настройка SSH-ключа (без изменений)
safe_exec "mkdir -p /home/devops/.ssh"
safe_exec "echo '$pubkey' > /home/devops/.ssh/authorized_keys.tmp"
safe_exec "mv /home/devops/.ssh/authorized_keys.tmp /home/devops/.ssh/authorized_keys"
safe_exec "chown -R devops:devops /home/devops/.ssh"
safe_exec "chmod 700 /home/devops/.ssh"
safe_exec "chmod 600 /home/devops/.ssh/authorized_keys"
echo -e "${GREEN}✅ SSH-ключ для devops настроен!${NC}"

# Финальная проверка SSH подключения
echo -e "${GREEN}==> Проверка SSH соединения...${NC}"
if safe_exec "ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no devops@localhost echo 'SSH подключение работает'"; then
    echo -e "${GREEN}✅ Настройка завершена успешно!${NC}"
else
    echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ]${NC} SSH подключение требует дополнительной проверки"
    echo -e "${GREEN}✅ Основная настройка завершена!${NC}"
fi
