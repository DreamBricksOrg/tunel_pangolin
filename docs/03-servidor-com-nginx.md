# Instalar o Pangolin num servidor que já tem nginx

Use este guia quando o servidor **já atende sites** pelo nginx nas portas 80 e 443 (o Pangolin
padrão também quer essas portas). A ideia: o Pangolin sobe só em portas internas e o nginx
repassa para ele os subdomínios do túnel. Os sites existentes não são alterados.

```
navegador ──► nginx :443 (certificado wildcard)
                ├─ inv.dominio, log.dominio, ...  ──► seus apps (como antes)
                └─ pangolin.dominio, *.dominio    ──► Traefik 127.0.0.1:8443 ──► túnel ──► seu PC
```

O nginx escolhe o `server_name` mais específico: hosts já configurados continuam indo para os
apps; só o que **não** tem site próprio cai no wildcard e vai para o Pangolin.

> O servidor é de produção: faça backup de `/etc/nginx`, rode `nginx -t` antes de recarregar e
> use `reload` (não `restart`).

---

## Antes de começar (manual)

1. **DNS** do domínio: registros `A` para `pangolin` e `*` apontando para o IP do servidor.
2. **Firewall do provedor**: liberar **UDP 51820** e **UDP 21820** (túnel). As portas 80/443 já estão abertas.
3. Uma **credencial de API do provedor de DNS**, restrita àquela zona, para o certificado wildcard
   (a validação wildcard é por DNS). Grave-a você mesmo no servidor, nunca em chat.

## 1. Pangolin em portas internas

Copie a pasta `pangolin/` deste repositório para `/opt/pangolin` e ajuste:

- Troque o domínio de exemplo pelo seu em `config/config.yml` e `config/traefik/dynamic_config.yml`.
- Gere o segredo **no servidor**: `openssl rand -hex 32` e coloque em `server.secret` (`config.yml`).
- No `docker-compose.yml`, deixe as portas web só no loopback e mantenha as UDP públicas:

```yaml
    ports:
      - 51820:51820/udp
      - 21820:21820/udp
      - 127.0.0.1:8443:443
      - 127.0.0.1:8080:80
```

- O certificado do Traefik não será usado (quem termina o TLS é o nginx). Para evitar tentativas
  inúteis na autoridade certificadora, aponte o `caServer` de `config/traefik/traefik_config.yml`
  para o ambiente de testes dela.

```bash
cd /opt/pangolin && sudo docker compose up -d
sudo docker compose logs pangolin | grep -i token     # token do setup inicial
```

## 2. Certificado wildcard

Com o certbot e o plugin DNS do seu provedor (no Debian/Ubuntu, `python3-certbot-dns-<provedor>`)
e a credencial gravada no servidor:

```bash
sudo certbot certonly --dns-<provedor> -d "*.seudominio.com" -d seudominio.com \
  --cert-name pangolin-wildcard.seudominio.com
```

A renovação é automática (timer do certbot).

## 3. nginx

```bash
sudo tar czf /root/nginx-backup-$(date +%F-%H%M).tgz /etc/nginx
```

`/etc/nginx/conf.d/pangolin-map.conf` (mapa para WebSocket):

```nginx
map $http_upgrade $pangolin_conn_upgrade {
    default upgrade;
    ""      close;
}
```

`/etc/nginx/sites-available/pangolin.seudominio.com` (com link em `sites-enabled`):

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name pangolin.seudominio.com *.seudominio.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name pangolin.seudominio.com *.seudominio.com;

    ssl_certificate     /etc/letsencrypt/live/pangolin-wildcard.seudominio.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pangolin-wildcard.seudominio.com/privkey.pem;
    client_max_body_size 0;

    location / {
        proxy_pass https://127.0.0.1:8443;
        proxy_ssl_verify off;
        proxy_ssl_server_name on;
        proxy_ssl_name $host;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $pangolin_conn_upgrade;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

## 4. Conferir

- `https://pangolin.seudominio.com/auth/initial-setup` responde 200 com certificado válido.
- Os sites que já existiam respondem como antes (compare os códigos HTTP antes e depois).
- Abra o painel, crie o admin (token do passo 1), a organização e um **Site** para cada PC.
- No PC, crie um perfil para este servidor, conforme a
  [seção 5 do guia de uso](02-usar-em-outros-computadores.md#5-usar-mais-de-um-servidor-perfis).

## Observações

- Subdomínios do domínio sem site próprio (e sem túnel ativo) passam a responder 404 do Pangolin.
- Certificados do mesmo domínio emitidos por outro método não são afetados.
