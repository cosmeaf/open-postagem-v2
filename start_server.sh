#!/bin/bash

# Diretório raiz do projeto
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_DIR="$PROJECT_DIR/log"
DJANGO_LOG="$LOG_DIR/django.log"
CELERY_LOG="$LOG_DIR/celery.log"
PORT="8000"
HOST="0.0.0.0"

# Gera log formatado
log_message() {
    local TYPE="$1"
    local DESC="$2"
    local MSG="$3"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $TYPE - $DESC - $MSG"
}

# Verifica e cria diretório e arquivos de log
prepare_logs() {
    mkdir -p "$LOG_DIR"
    [ ! -f "$DJANGO_LOG" ] && touch "$DJANGO_LOG"
    [ ! -f "$CELERY_LOG" ] && touch "$CELERY_LOG"
}

start() {
    prepare_logs
    log_message "INFO" "START" "Iniciando servidor Django e Celery..." | tee -a "$DJANGO_LOG"
    
    # Start Django
    cd "$PROJECT_DIR"
    nohup python manage.py runserver "$HOST:$PORT" >> "$DJANGO_LOG" 2>&1 &
    DJANGO_PID=$!
    echo $DJANGO_PID > "$LOG_DIR/django.pid"
    
    # Start Celery
    nohup celery -A core worker --loglevel=info >> "$CELERY_LOG" 2>&1 &
    CELERY_PID=$!
    echo $CELERY_PID > "$LOG_DIR/celery.pid"

    log_message "INFO" "START" "Serviços iniciados com sucesso." | tee -a "$DJANGO_LOG"
}

stop() {
    log_message "INFO" "STOP" "Parando servidor..." | tee -a "$DJANGO_LOG"

    if [ -f "$LOG_DIR/django.pid" ]; then
        kill -9 $(cat "$LOG_DIR/django.pid") && rm "$LOG_DIR/django.pid"
        log_message "INFO" "STOP" "Django finalizado." | tee -a "$DJANGO_LOG"
    fi

    if [ -f "$LOG_DIR/celery.pid" ]; then
        kill -9 $(cat "$LOG_DIR/celery.pid") && rm "$LOG_DIR/celery.pid"
        log_message "INFO" "STOP" "Celery finalizado." | tee -a "$CELERY_LOG"
    fi
}

status() {
    echo "STATUS:"
    if [ -f "$LOG_DIR/django.pid" ] && kill -0 $(cat "$LOG_DIR/django.pid") 2>/dev/null; then
        echo " - Django: Ativo (PID $(cat "$LOG_DIR/django.pid"))"
    else
        echo " - Django: Inativo"
    fi

    if [ -f "$LOG_DIR/celery.pid" ] && kill -0 $(cat "$LOG_DIR/celery.pid") 2>/dev/null; then
        echo " - Celery: Ativo (PID $(cat "$LOG_DIR/celery.pid"))"
    else
        echo " - Celery: Inativo"
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 2
        start
        ;;
    status)
        status
        ;;
    *)
        echo "Uso: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
