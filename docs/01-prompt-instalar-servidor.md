# Prompt: instalar o Pangolin em um servidor novo

Cole o prompt abaixo num agente de IA que execute comandos no seu PC, preenchendo os campos entre `< >`.
Antes de colar, faça a parte manual descrita em **"Antes de começar"**.

---

## Antes de começar (manual, você faz)

1. **DNS** (no painel do provedor onde o domínio está registrado):
   | Tipo | Nome | Valor |
   |---|---|---|
   | A | `*` | IP do servidor |

   Não precisa mexer no registro do domínio raiz (`@`) — o site principal continua onde está.

2. **Firewall do provedor** (regras de entrada / security group, origem `0.0.0.0/0`):
   | Protocolo | Porta |
   |---|---|
   | TCP | 80 |
   | TCP | 443 |
   | UDP | 51820 |
   | UDP | 21820 |

3. Tenha a **chave SSH privada** salva num arquivo no seu PC (não cole o conteúdo no chat — passe só o caminho).

---

## Prompt

```text
Quero instalar o Pangolin (self-hosted, Community Edition) num servidor novo para expor
apps do meu localhost em subdomínios HTTPS do meu domínio.

Dados:
- Chave SSH (caminho no meu PC): <C:\caminho\da\chave.key>
- IP do servidor: <000.000.000.000>
- Usuário SSH: <ubuntu>
- Domínio base: <meudominio.com.br>
- Subdomínio do painel: pangolin.<meudominio.com.br>

Já fiz manualmente: registro DNS A "*" apontando para o IP, e liberei no firewall da nuvem
TCP 80, 443 e UDP 51820, 21820.

Regras:
- NÃO peça para eu colar a chave privada; use o arquivo pelo caminho com ssh -i.
- Primeiro inspecione o servidor só em modo leitura (SO, arquitetura, Docker, iptables,
  portas em uso) e me mostre o resultado antes de alterar algo.
- Avise antes de cada etapa que altera o servidor.

Passos esperados:
1. Conferir que pangolin.<dominio> e um subdomínio qualquer (ex.: teste.<dominio>) resolvem
   para o IP (nslookup no 8.8.8.8).
2. Instalar Docker + Compose (no Ubuntu: apt install docker.io docker-compose-v2
   iptables-persistent).
3. Liberar no iptables do próprio servidor TCP 80/443 e UDP 51820/21820. Atenção: algumas
   imagens de nuvem já vêm com uma regra REJECT na chain INPUT — as regras ACCEPT precisam ser
   inseridas ANTES dela (iptables -I INPUT <posição>). Salvar com netfilter-persistent save.
4. Criar /opt/pangolin seguindo o guia oficial de instalação manual com Docker Compose:
   https://docs.pangolin.net/self-host/manual/docker-compose
   (consulte a página para pegar a versão atual dos arquivos). Estrutura:
     docker-compose.yml           (serviços pangolin, gerbil, traefik)
     config/config.yml            (dashboard_url, base_domain, server.secret, flags)
     config/traefik/traefik_config.yml
     config/traefik/dynamic_config.yml
     config/db/ config/letsencrypt/ config/traefik/logs/
   - Substitua os exemplos pelo meu domínio.
   - Gere o server.secret NO SERVIDOR (openssl rand -hex 32), não no chat.
   - Pode omitir o e-mail do ACME no traefik_config.yml.
   - Mantenha flags.disable_signup_without_invite: true.
5. Subir com docker compose up -d e conferir que os 3 containers estão de pé
   (pangolin deve ficar "healthy").
6. Testar de fora: http://pangolin.<dominio> deve responder (302) e
   https://pangolin.<dominio>/auth/initial-setup deve responder 200 com certificado válido.
   Se o certificado falhar por timeout, é firewall: pare e me avise, NÃO fique tentando
   (a autoridade certificadora bloqueia após várias falhas por ~1h). Depois que eu liberar, reinicie
   só o traefik.
7. Pegar o token de setup em `docker compose logs pangolin` (linha "Token:") e me passar
   junto com o link https://pangolin.<dominio>/auth/initial-setup.
8. Salvar uma cópia dos arquivos de configuração (sem o secret) numa pasta local
   pangolin/ no meu projeto.

No final, me dê um resumo: o que foi instalado, onde, e os próximos passos
(criar admin, criar organização, criar um site "Pangolin Site" para cada PC).
```

---

> **O servidor já tem nginx ou apache nas portas 80 e 443?** O prompt acima assume um servidor
> "cru". Nesse caso siga o [guia com nginx](03-servidor-com-nginx.md): o Pangolin fica em portas
> internas e o nginx repassa os subdomínios.

## Depois da instalação

1. Abra `https://pangolin.<dominio>/auth/initial-setup`, cole o token e crie o admin.
2. Crie uma organização (ex.: `local`).
3. Para cada computador que vai expor apps, siga o
   [02-usar-em-outros-computadores.md](02-usar-em-outros-computadores.md).

## Referência: instalação atual

| Item | Valor |
|---|---|
| Servidor | Debian 12 x86_64, `52.67.24.199`, com nginx nas portas 80/443 (veja o [guia com nginx](03-servidor-com-nginx.md)) |
| Painel | https://pangolin.dbpe.com.br |
| Pasta no servidor | `/opt/pangolin` |
| Cópia local da config | `pangolin/` (sem o secret) |
| Comandos úteis (no servidor) | `cd /opt/pangolin && sudo docker compose ps` · `sudo docker compose logs -f` · `sudo docker compose pull && sudo docker compose up -d` (atualizar) |
