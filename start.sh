#!/bin/sh
# Script de inicialização para Railway
# Este script é executado quando o container inicia

# Criar diretórios necessários se não existirem
mkdir -p /app/storages
mkdir -p /app/statics/media
mkdir -p /app/statics/qrcode
mkdir -p /app/statics/senditems

# Executar a aplicação
exec /app/whatsapp rest

