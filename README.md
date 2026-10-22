# Tunel Pangolin

Exponha serviços do seu computador em subdomínios HTTPS do seu próprio domínio, usando um
servidor [Pangolin](https://github.com/fosrl/pangolin) self-hosted.

```powershell
tunel 8001 meuapp
```

```
https://meuapp.seudominio.com  ──►  servidor (Pangolin + Traefik + Gerbil)  ══ túnel criptografado ══►  seu PC: localhost:8001
```

- HTTPS automático em qualquer subdomínio.
- Links públicos, sem login.
- Vários túneis ao mesmo tempo no mesmo PC, compartilhando uma única conexão.
- Painel web para ver sites, recursos e tráfego.
- Nenhuma porta aberta no seu PC ou roteador — a conexão é só de saída.

## Estrutura

| Caminho | O que é |
|---|---|
| [`pangolin/`](pangolin/) | Configuração do servidor (compose com Pangolin, Gerbil e Traefik) |
| [`tunel/`](tunel/) | Comando `tunel` — `tunel.ps1` + `tunel.cmd` (Windows), `tunel.sh` (Linux/macOS) |
| [`site-teste/`](site-teste/) | Servidor Node sem dependências para testar o túnel (mostra headers e se veio pelo túnel) |
| [`docs/01-prompt-instalar-servidor.md`](docs/01-prompt-instalar-servidor.md) | Prompt para um agente de IA instalar o servidor |
| [`docs/02-usar-em-outros-computadores.md`](docs/02-usar-em-outros-computadores.md) | Como configurar o `tunel` em outro PC (Windows, Ubuntu, Fedora) e usar vários servidores (perfis) |
| [`docs/03-servidor-com-nginx.md`](docs/03-servidor-com-nginx.md) | Instalar o Pangolin num servidor que já tem nginx e apps em produção |

## Como funciona

1. **Servidor** — o Pangolin roda num servidor com IP público e DNS wildcard
   `*.seudominio.com` apontando para ele. O Traefik emite um certificado por subdomínio sob demanda.
2. **Site** — cada computador é um *site* no Pangolin, com ID e Secret próprios.
3. **`tunel`** — gera um *blueprint* com os recursos HTTP públicos (`subdominio → localhost:porta`)
   e roda `pangolin up site --blueprint-file ...`. O Pangolin recarrega o arquivo sozinho, então
   novos túneis entram na conexão existente sem reiniciar.

## Uso rápido (Windows)

```powershell
tunel                       # exemplo de uso
tunel --help                # ajuda completa
tunel 8001 meuapp           # https://meuapp.<dominio> -> localhost:8001
tunel 8001:api 5173:front   # vários túneis num comando
tunel list                  # conexão e túneis ativos
tunel stop                  # encerra tudo
```

Em outro terminal, outro `tunel` adiciona mais um túnel à mesma conexão.
**Ctrl+C** (ou fechar a janela) desativa os túneis daquele terminal.

Verificações automáticas:
- porta ou nome já usados por outro túnel ativo → recusa;
- nada escutando na porta local → aviso (o link dá 502 até o app subir);
- `pangolin` rodando fora do `tunel` (manual ou serviço) → recusa, com instruções;
- detecta se o app escuta em IPv4 (`127.0.0.1`) ou IPv6 e aponta o destino certo.

## Instalação

### Servidor

Siga [`docs/01-prompt-instalar-servidor.md`](docs/01-prompt-instalar-servidor.md). Resumo:

1. DNS: registro `A` `*` → IP do servidor.
2. Firewall: TCP 80, 443 e UDP 51820, 21820 — tanto no firewall do provedor quanto no do
   próprio servidor.
3. Runtime de containers com compose + arquivos de [`pangolin/`](pangolin/) em `/opt/pangolin`
   (troque o domínio e gere o `server.secret` com `openssl rand -hex 32`).
4. `docker compose up -d` → `https://pangolin.<dominio>/auth/initial-setup` com o token dos logs.

### Cada computador

Siga [`docs/02-usar-em-outros-computadores.md`](docs/02-usar-em-outros-computadores.md). Resumo:

1. Painel → **Sites → Add Site** (Pangolin Site) → copie ID e Secret.
2. Instale o CLI do Pangolin.
3. Copie `tunel/tunel.config.example.json` para `tunel/tunel.config.json` e preencha.
4. Coloque a pasta `tunel` no PATH: no Windows, duplo clique em `tunel/add_to_path.cmd`.

### Vários servidores no mesmo computador (perfis, Windows)

Cada servidor Pangolin é um **perfil**: um arquivo `tunel/tunel.config.<perfil>.json` (copie o
`tunel.config.example.json`). O `tunel.config.json` é o perfil padrão.

```
tunel 8001 meuapp                 # perfil padrão
tunel -p outro 8001 meuapp        # https://meuapp.<domínio do perfil "outro">
tunel list                        # todos os perfis
tunel -p outro stop               # encerra só o perfil "outro"
```

Cada perfil tem conexão, estado e supervisor próprios; a mesma porta local pode ser exposta em
perfis diferentes. Também vale a variável `TUNEL_PROFILE`.

## Segurança

- `tunel/tunel.config.json` contém o Secret do site e **não é versionado** (`.gitignore`).
- Um mesmo site (ID/Secret) não deve rodar em dois PCs ao mesmo tempo — crie um site por PC.
- Os links criados pelo `tunel` são públicos. Não exponha nada sensível sem autenticação própria.
- Não crie pelo painel um recurso com o mesmo subdomínio usado pelo `tunel`: o recurso manual
  vem com login ligado e tem prioridade.

## Limitações

- Um túnel novo leva ~5–20 s para ficar ativo (recarga do blueprint).
- Recursos desativados continuam listados no painel (com `enabled: false`); apague-os lá se quiser.
- `tunel list` / `stop`, as verificações e os perfis (`-p`) existem só na versão Windows; o
  `tunel.sh` tem o modo básico (aceita `-p <perfil>` para escolher o arquivo de configuração).
