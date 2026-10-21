# Plano: vídeo tutorial do tunel_pangolin (60 s)

**Ângulo:** passo a passo para sair do zero e ter `localhost` com https público, em 7 passos.
**Tom:** didático e limpo. 1920×1080, 30 fps, 60,4 s. O teaser curto (23,6 s) ficou em `brag-curto.mp4`.

| Passo | Tempo | O que mostra |
|---|---|---|
| Abertura | 0,0–3,8 | "Do zero ao link https em 7 passos" |
| 1. Baixar o projeto | 3,9–10,4 | `git clone https://github.com/juliobalbino/tunel_pangolin`, `cd`, `ls` (destaque da pasta `tunel`) |
| 2. Abrir o painel | 10,5–16,5 | navegador abre `pangolin.dbpe.com.br` |
| 3. Fazer login | 16,6–22,6 | e-mail, senha, Entrar |
| 4. Criar o site | 22,7–30,7 | Sites → Add Site → Pangolin Site → nome → Create Site → ID e Secret (aviso: só aparece agora) |
| 5. Instalar o Pangolin CLI | 30,8–37,8 | Windows (instalador .msi) e Ubuntu/Fedora (`curl ... \| bash`) |
| 6. Colocar o secret | 37,9–44,9 | `tunel/tunel.config.json` com ID e Secret; aviso para não compartilhar |
| 7. Abrir o túnel | 45,0–56,0 | `cd tunel`, `.\tunel 8001 meuapp`, link, app no navegador; Linux, Ctrl+C e `tunel list` |
| Final | 56,1–60,4 | "Pronto. Localhost com https." + repositório + dica de perfis |

**Dados:** ID, secret, e-mail e senha mostrados são fictícios. Os domínios são os do servidor padrão (`dbpe.com.br`).
**Som:** Lá menor, pad e arpejo com eco; baixo, bumbo e hats só nas cenas de ação; chimes sobem a escala a cada passo.
