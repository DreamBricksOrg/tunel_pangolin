# Usar o túnel em outro computador

Objetivo: em qualquer PC (Windows, Ubuntu ou Fedora), rodar

```bash
tunel 8001 meuapp
```

e ter `https://meuapp.juliobalbino.com.br` → `http://localhost:8001` daquele PC, público e com HTTPS.

> **Regra de ouro:** cada computador é **um site** no Pangolin, com ID e Secret próprios.
> Nunca reutilize o `tunel.config.json` de outro PC.

Nenhuma porta precisa ser aberta no PC nem no roteador: a conexão é só de saída.

---

## 1. Criar o site no painel (uma vez por PC — igual para todos os sistemas)

1. Acesse https://pangolin.juliobalbino.com.br e faça login.
2. **Sites → Add Site**
   - Tipo: **Pangolin Site (Recommended)**
   - Name: o nome do PC (ex.: `notebook`, `pc-trabalho`, `fedora-casa`)
3. Copie o **ID** e o **Secret** — o Secret só aparece nessa tela.
4. Clique em **Create Site**. Não precisa rodar o comando que o painel mostra nem criar nada em
   **Resources** — o script `tunel` faz isso.

## 2. Arquivo de configuração (igual para todos os sistemas)

Copie a pasta `tunel` para o PC novo **sem** o `tunel.config.json` do outro PC, e crie um novo
nessa pasta com os dados **deste PC**:

```json
{
  "id": "ID_DO_SITE_DESTE_PC",
  "secret": "SECRET_DO_SITE_DESTE_PC",
  "endpoint": "https://pangolin.juliobalbino.com.br",
  "domain": "juliobalbino.com.br",
  "pangolin": "pangolin"
}
```

- `pangolin`: deixe `"pangolin"` se o comando funciona em qualquer terminal; senão, coloque o
  caminho completo do executável.
- Esse arquivo contém o Secret: não compartilhe nem cole em chats.

Arquivos da pasta `tunel`:

| Arquivo | Usado em |
|---|---|
| `tunel.ps1` + `tunel.cmd` | Windows |
| `tunel.sh` | Ubuntu / Fedora (e macOS) |
| `tunel.config.json` | todos (um por PC) |

---

## 3A. Windows

**Instalar o CLI do Pangolin**

1. Baixe e execute o instalador:
   https://github.com/fosrl/cli/releases/latest/download/pangolin-cli_windows_installer.msi
2. Abra um terminal **novo** e confira: `pangolin --help`

**Instalar o `tunel`**

1. Coloque a pasta em `C:\Tools\tunel` (ou onde preferir) com o `tunel.config.json` deste PC.
2. Adicione ao PATH: Menu Iniciar → "Editar as variáveis de ambiente do sistema" →
   **Variáveis de Ambiente** → *Variáveis do usuário* → **Path** → **Novo** → `C:\Tools\tunel`.
3. Feche e abra o terminal. Teste: `tunel 8001 meuapp -DryRun`

Se o `pangolin` não estiver no PATH, use no config o caminho com barras duplas, ex.:
`"pangolin": "C:\\Program Files\\Pangolin\\pangolin.exe"`.

## 3B. Ubuntu (22.04 / 24.04)

```bash
# Dependências (normalmente já vêm instaladas)
sudo apt update && sudo apt install -y curl python3

# CLI do Pangolin (detecta a arquitetura e coloca no PATH)
curl -fsSL https://static.pangolin.net/get-cli.sh | bash
pangolin --help

# Script tunel
mkdir -p ~/.local/share/tunel
cp tunel.sh ~/.local/share/tunel/
nano ~/.local/share/tunel/tunel.config.json      # cole o JSON da seção 2
chmod +x ~/.local/share/tunel/tunel.sh
chmod 600 ~/.local/share/tunel/tunel.config.json
mkdir -p ~/.local/bin
ln -sf ~/.local/share/tunel/tunel.sh ~/.local/bin/tunel

# Garantir ~/.local/bin no PATH (no Ubuntu já costuma estar; abra um terminal novo depois)
grep -q '.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# Teste
tunel 8001 meuapp --dry-run
```

## 3C. Fedora (39+)

```bash
# Dependências (normalmente já vêm instaladas)
sudo dnf install -y curl python3

# CLI do Pangolin
curl -fsSL https://static.pangolin.net/get-cli.sh | bash
pangolin --help

# Script tunel
mkdir -p ~/.local/share/tunel
cp tunel.sh ~/.local/share/tunel/
nano ~/.local/share/tunel/tunel.config.json      # cole o JSON da seção 2
chmod +x ~/.local/share/tunel/tunel.sh
chmod 600 ~/.local/share/tunel/tunel.config.json
mkdir -p ~/.local/bin
ln -sf ~/.local/share/tunel/tunel.sh ~/.local/bin/tunel

# No Fedora ~/.local/bin já está no PATH por padrão; abra um terminal novo e teste
tunel 8001 meuapp --dry-run
```

Notas do Fedora:
- **firewalld** não precisa de ajuste: o túnel só faz conexões de saída e o app é acessado via
  `localhost`.
- Se o `nano` não existir: `sudo dnf install -y nano` (ou use `vi`).

> Se o `tunel.sh` foi copiado de um PC Windows e der erro `bad interpreter` ou `\r`, rode
> `sed -i 's/\r$//' ~/.local/share/tunel/tunel.sh`.

---

## 4. Usar (todos os sistemas)

Com seu app rodando localmente:

```bash
tunel 8001 meuapp           # https://meuapp.juliobalbino.com.br  -> localhost:8001
tunel 8001                  # https://p8001.juliobalbino.com.br   -> localhost:8001
tunel 8001:api 5173:front   # vários ao mesmo tempo
```

Só ver o que seria criado: `-DryRun` no Windows, `--dry-run` no Linux.

**Windows — comandos extras** (o `tunel.sh` do Linux ainda tem só o modo básico):

```powershell
tunel                   # mostra um exemplo de uso
tunel --help            # ajuda completa
tunel list              # conexão e túneis ativos
tunel stop              # encerra todos os túneis e a conexão
```

- **Vários túneis no mesmo PC:** abra `tunel` em quantos terminais quiser. A primeira chamada
  conecta o Pangolin em segundo plano; as seguintes só adicionam o túnel à conexão existente.
- **Verificações:** recusa porta ou nome já usados por outro túnel ativo; avisa se nada está
  escutando na porta local; recusa se houver um `pangolin` rodando fora do `tunel`.
- **Ctrl+C ou fechar a janela** desativa os túneis daquele terminal (o link volta a dar 404).
  Sem túneis ativos, a conexão é encerrada sozinha após ~30s.
- Estado e logs ficam em `%LOCALAPPDATA%\tunel`.

- O terminal fica aberto enquanto o túnel estiver ativo. **Ctrl+C** encerra.
- O primeiro acesso a um subdomínio novo pode levar alguns segundos (emissão do certificado).
- Os endereços são **públicos, sem login**.

### Teste rápido

Na pasta do projeto há um site de teste (precisa de Node.js):

```bash
node site-teste/server.js        # sobe em localhost:3000
tunel 3000 teste-notebook
```

Ou, sem Node, no Linux: `python3 -m http.server 3000`.

Abra `https://teste-notebook.juliobalbino.com.br`. Com o site de teste, deve aparecer o selo verde
**"Acessado pelo túnel"**.

---

## Regras importantes

- **Subdomínio é único.** Se dois PCs usarem o mesmo nome ao mesmo tempo, eles brigam. Use nomes
  distintos por PC (ex.: `api-casa`, `api-note`).
- **Não crie pelo painel um recurso com o mesmo subdomínio** que o script usa. O recurso criado
  manualmente vem com login ligado e tem prioridade — o link passa a pedir login.
- Um mesmo site (ID/Secret) **não pode** rodar em dois PCs ao mesmo tempo.

## Problemas comuns

| Sintoma | Causa provável | Solução |
|---|---|---|
| Link pede login do Pangolin | Recurso duplicado criado pelo painel para o mesmo subdomínio | Painel → Resources → apague o que **não** começa com "tunel" |
| `404 page not found` | Túnel não está rodando, ou app local fora do ar | Confira o terminal do `tunel` e se `http://localhost:PORTA` abre no PC |
| `502 Bad Gateway` | Túnel ativo, mas nada escutando na porta | Suba o app local na porta informada |
| `pangolin: command not found` / não reconhecido | CLI fora do PATH | Terminal novo; ou caminho completo em `"pangolin"` no config (`which pangolin` no Linux) |
| `tunel: command not found` (Linux) | `~/.local/bin` fora do PATH | Abra terminal novo ou `export PATH="$HOME/.local/bin:$PATH"` |
| Erro de execução de script (Windows) | Política de execução do PowerShell | Use `tunel.cmd` (já roda com `-ExecutionPolicy Bypass`) |
| `bad interpreter` / `$'\r'` (Linux) | Arquivo com quebra de linha do Windows | `sed -i 's/\r$//' tunel.sh` |
| Site aparece *Offline* no painel | ID/Secret errados ou de outro PC | Confira o `tunel.config.json` deste PC |

## Remover um PC

Painel → **Sites** → apague o site do PC. Os recursos dele param de funcionar e podem ser
apagados em **Resources**. No PC, apague a pasta do `tunel` (e no Linux o link
`~/.local/bin/tunel`).
