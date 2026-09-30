#!/usr/bin/env bash
# Text -> combat motion with AnimationGPT (MotionGPT fine-tuned on the CombatMotion game
# animations), then import into the game.
#
# Needs network access to: github.com, huggingface.co (flan-t5-base for MotionGPT),
# drive.google.com / drive.usercontent.google.com (the AnimationGPT and evaluator weights)
# and pypi.org. MotionGPT's T5-base runs fine on a CPU (a few seconds per prompt); a GPU
# only makes it faster.
#
#   ./run_animationgpt.sh            # generate + import into assets/motion_generated
#   INSTALL=1 ./run_animationgpt.sh  # ... and copy the clips over assets/motion
#
# Steps follow https://github.com/fyyakaxyy/AnimationGPT (README, "Tutorial").
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
WORK="${WORK:-$HOME/agpt}"
AGPT_MODEL_ID="1myqSqe41JpJCd0JaIu0FVPf93FI0A22L"      # AGPT model (MotionGPT trained on CMP)
MOTIONGPT_COMMIT="0499f16df4ddde44dfd72a7cbd7bd615af1b1a94"
mkdir -p "$WORK" && cd "$WORK"

[ -d MotionGPT ] || { git clone https://github.com/OpenMotionLab/MotionGPT.git; (cd MotionGPT && git checkout "$MOTIONGPT_COMMIT"); }
[ -d AnimationGPT ] || git clone https://github.com/fyyakaxyy/AnimationGPT.git
cd MotionGPT

if [ ! -f .deps_done ]; then
  pip install -r requirements.txt
  pip install gdown
  python -m spacy download en_core_web_sm
  mkdir -p deps
  (cd deps && bash ../prepare/prepare_t5.sh && bash ../prepare/download_t2m_evaluators.sh)
  touch .deps_done
fi
[ -f mGPT.ckpt ] || gdown "$AGPT_MODEL_ID" -O mGPT.ckpt
cp ../AnimationGPT/config_AGPT.yaml .
cp -r ../AnimationGPT/tools . 2>/dev/null || true

# MotionGPT's demo only assigns `device` for the GPU; make it work on a CPU too
if ! grep -q "device = torch.device('cpu')" demo.py; then
  python - <<'PY'
import re
s = open('demo.py').read()
s = s.replace('''        device = torch.device("cuda")
''', '''        device = torch.device("cuda")
    else:
        device = torch.device('cpu')
''')
open('demo.py', 'w').write(s)
PY
fi
if ! nvidia-smi >/dev/null 2>&1; then sed -i "s/^ACCELERATOR: .*/ACCELERATOR: 'cpu'/" config_AGPT.yaml; fi

python "$HERE/make_input.py" "$HERE/prompts.json" > input.txt
python demo.py --cfg ./config_AGPT.yaml --example ./input.txt
RESULTS="$(ls -dt results/mgpt/*AGPT*/samples_* | head -1)"
echo "results in $RESULTS"

cd "$REPO/tools/motion"
python text2motion/import_batch.py --results "$WORK/MotionGPT/$RESULTS" --prompts text2motion/prompts.json \
  --out "$REPO/assets/motion_generated" ${INSTALL:+--install}
