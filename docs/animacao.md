# Animação: de onde vêm os movimentos

O boneco continua sendo um **ragdoll ativo** (o corpo físico persegue as poses-alvo), mas as
poses-alvo agora vêm de **clipes de animação esquelética** em `assets/motion/*.json`, e não mais de
curvas escritas à mão dentro do `ProceduralAnimator`. O jogo só toca os clipes, mistura entre eles
e adapta ao terreno; quem cria os clipes é o pipeline em `tools/motion/`.

## Ferramentas de texto → animação de esqueleto (pesquisa)

| Ferramenta | O que faz | Pesos / requisitos |
|---|---|---|
| **AnimationGPT** (MotionGPT ajustado no CombatMotion) | Texto → movimento de **combate** (katana, ataques leves/pesados, defesa, dano), saída = 22 juntas SMPL (`.npy`) | pesos no Google Drive, ~T5-base (roda em CPU); é a mais próxima do que o jogo precisa |
| **HY-Motion 1.0** (Tencent) | DiT de 1 bilhão de parâmetros, texto → SMPL-H | pesos no Hugging Face, 24–26 GB de VRAM |
| **Kimodo** (NVIDIA) | difusão cinemática, texto + restrições (esqueleto SOMA/SMPL-X, exporta BVH/NPZ) | pesos no Hugging Face, ~17 GB de VRAM (encoder LLM2Vec) |
| MDM, MoMask, T2M-GPT, MotionGPT | modelos clássicos treinados no HumanML3D (movimentos do dia a dia, poucos golpes de espada) | pesos no Google Drive / Hugging Face |

Neste ambiente (nuvem, 4 CPUs, sem GPU) o firewall bloqueia `huggingface.co` e `drive.google.com`,
então **nenhum desses modelos pôde ser baixado nem executado aqui**. Em vez de deixar o jogo sem
animação boa, o pipeline foi montado para aceitar a saída de qualquer um deles e, enquanto isso,
os clipes vêm de:

* **captura de movimento real** (caminhada, corrida, rolamento) dos clipes do DeepMimic que
  acompanham o pacote `pybullet_data` (licença zlib; o projeto DeepMimic é MIT, mas não documenta a
  origem dos dados originais — confira antes de distribuir comercialmente),
* **poses-chave autorais** para tudo o que é de combate (`tools/motion/clips_*.py`), feitas sobre o
  esqueleto real do boneco.

### Usar o AnimationGPT (quando a rede permitir)

Libere `github.com`, `huggingface.co`, `drive.google.com` e `drive.usercontent.google.com` no
ambiente e rode:

```bash
tools/motion/text2motion/run_animationgpt.sh            # gera em assets/motion_generated/
INSTALL=1 tools/motion/text2motion/run_animationgpt.sh  # e instala por cima de assets/motion/
```

Os prompts ficam em `tools/motion/text2motion/prompts.json` (vocabulário do CombatMotion). Cada
saída é retargetada (`import_smpl.py`), ganha o instante do golpe (pico de velocidade da ponta da
lâmina, o jogo alinha isso à janela de dano do ataque) e uma folha de contato PNG para revisar. O
script segue o tutorial do repositório do AnimationGPT; o importador foi testado com juntas
sintéticas (`python3 tools/motion/text2motion/selftest.py`), mas **não com saídas reais do modelo**.

## Como o jogo usa os clipes

* `MotionClip` / `MotionPose` (GDScript): amostragem por frame com slerp; cada clipe guarda a posição
  do quadril, uma rotação local por parte do rig, contatos dos pés e (para armas) a empunhadura no
  referencial do peito.
* `ProceduralAnimator`:
  * locomoção: *idle / walk / run / sprint* misturados por velocidade numa fase de passada comum,
    com **stride warping** (a passada é esticada para casar com a velocidade) e **orientation
    warping** (ao andar de lado ou de costas as pernas giram e o tronco continua olhando para o alvo);
  * ações (ataques, defesa, rolamento, reações...): o clipe é escolhido pela ação; a troca usa
    **inertialization** (o deslocamento entre a pose anterior e a nova decai) em vez de fade;
  * pés: os contatos do clipe fixam os pés no terreno real (raycast + IK de duas juntas); pé fora de
    alcance é arrastado no chão, quadril só desce no que sobrar;
  * braços: FK do clipe, ou IK de duas juntas até a empunhadura de duas mãos (a mão esquerda solta a
    espada quando o golpe abre mais do que o braço curto alcança);
  * cabeça: olhar para o alvo por cima do clipe.
* `AttackLibrary` guarda só a parte de jogo de cada golpe (dano, janela ativa, avanço); o clipe
  (`"clip": "katana_light_1"`) traz a pose. O instante do golpe do clipe (`meta.strike`) é alinhado ao
  meio da janela ativa.

## Pipeline offline (`tools/motion/`)

```bash
pip install numpy scipy matplotlib pybullet   # pybullet só para extrair os clipes de captura
python3 tools/motion/build_all.py             # gera tudo em assets/motion (DM_MOTIONS=<pybullet_data/data/motions>)
python3 tools/motion/check_clips.py           # emenda de loops, saltos de rotação, chão
python3 tools/motion/diag.py clips_katana light_2   # alcance dos braços por frame
```

* `mo_rig.py`: cinemática direta do rig real (`rig.json`, o mesmo do jogo), IK de duas juntas.
* `dm_import.py`, `locomotion.py`, `posefx.py`: retarget dos clipes de captura (as rotações copiam
  direto: mesma topologia), contatos, calibração do chão, corrida → sprint, andar → agachado.
* `authoring.py`, `kit.py`, `clips_*.py`: poses-chave (quadril, coluna, cabeça, pés, empunhadura) com
  curvas PCHIP; empunhadura no referencial do peito com a torção do tronco explícita (o quadril
  lidera o peito no tempo), aresta da lâmina que acompanha o corte, pés com passo de avanço.
* `import_smpl.py`, `text2motion/`: saída de qualquer modelo texto → movimento (22 juntas SMPL, layout
  HumanML3D) vira clipe do jogo.
* `preview.py`: folhas de contato (boneco de palitos com as proporções reais) para revisar sem abrir
  a engine.
