#!/usr/bin/env python3
"""Gera os icones .ico usados nos botoes da barra de tarefas do Windows
(thumbnail toolbar: aleatorio / anterior / tocar-pausar / proxima / repetir).

Uso (a partir da raiz do projeto):
    pip install pillow
    python tools/generate_taskbar_icons.py

Saida: assets/icons/taskbar_<glifo>_<tema>.ico, onde <tema> e o tema do
SISTEMA para o qual o icone foi pensado:
  - "dark"  -> barra de tarefas escura  -> glifo claro (quase branco)
  - "light" -> barra de tarefas clara   -> glifo escuro (quase preto)

O codigo nativo (windows/runner/taskbar_media_controls.cpp) escolhe o
sufixo lendo SystemUsesLightTheme no registro. Se mudar os nomes aqui,
mude la tambem.

Cada .ico traz varios tamanhos (16..48 + 256): o Windows pede o tamanho
conforme o DPI (16px a 100%, 20px a 125%, 24px a 150%, 32px a 200%...).
"""
from pathlib import Path

from PIL import Image, ImageDraw

OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "icons"

MASTER = 256            # tamanho final da imagem-mestra
SUPERSAMPLE = 4         # desenha em 1024 e reduz, para suavizar as bordas
ICO_SIZES = [(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48), (256, 256)]

# Cores do glifo por tema do sistema. O destaque (repeat ligado) usa o
# roxo do app (AppColors.accentVariant no escuro, AppColors.accent no claro).
NEUTRAL = {"dark": (245, 243, 247), "light": (28, 24, 36)}
ACCENT = {"dark": (183, 148, 246), "light": (139, 92, 246)}
REPEAT_OFF_ALPHA = 0.55  # "repetir desativado" fica visivelmente apagado

GRID = 24.0  # as formas abaixo sao desenhadas numa grade de 24x24


def _px(points):
    s = MASTER * SUPERSAMPLE / GRID
    return [(x * s, y * s) for x, y in points]


def _rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


# --- Formas (coordenadas na grade 24x24) -------------------------------
PLAY = [[(7.5, 4), (7.5, 20), (20, 12)]]
PAUSE = [_rect(5.5, 4, 10, 20), _rect(14, 4, 18.5, 20)]
PREVIOUS = [_rect(4, 4, 7, 20), [(20, 4), (20, 20), (8.5, 12)]]
NEXT = [_rect(17, 4, 20, 20), [(4, 4), (4, 20), (15.5, 12)]]

# Dois lacos com ponta de seta (repetir). Escalado ~0.92 em torno do centro.
def _shrink(points, k=0.92, c=12.0):
    return [(c + (x - c) * k, c + (y - c) * k) for x, y in points]


REPEAT = [
    _shrink([(7, 7), (17, 7), (17, 10), (21, 6), (17, 2), (17, 5),
             (5, 5), (5, 11), (7, 11)]),
    _shrink([(17, 17), (7, 17), (7, 14), (3, 18), (7, 22), (7, 19),
             (19, 19), (19, 13), (17, 13)]),
]
# Aleatorio: duas setas que se cruzam (linhas grossas + ponta de seta).
# Cada linha e (pontos, espessura) na grade 24x24.
SHUFFLE_LINES = [
    ([(3.5, 6.5), (8.5, 6.5), (15, 17.5), (16.5, 17.5)], 2.2),
    ([(3.5, 17.5), (8.5, 17.5), (15, 6.5), (16.5, 6.5)], 2.2),
]
SHUFFLE_HEADS = [
    [(16.0, 14.0), (16.0, 21.0), (21.0, 17.5)],
    [(16.0, 3.0), (16.0, 10.0), (21.0, 6.5)],
]

# "1" no meio do laco (repetir uma musica).
ONE = [[(10.0, 10.6), (12.2, 8.8), (13.8, 8.8), (13.8, 15.6),
        (12.0, 15.6), (12.0, 10.9), (10.7, 11.9)]]


def render(shapes, color, alpha=1.0, lines=()):
    big = MASTER * SUPERSAMPLE
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rgba = (*color, int(round(255 * alpha)))
    for poly in shapes:
        draw.polygon(_px(poly), fill=rgba)
    for points, width in lines:
        draw.line(_px(points), fill=rgba, width=int(round(width * big / GRID)),
                  joint="curve")
    return img.resize((MASTER, MASTER), Image.LANCZOS)


def save_ico(name, theme, shapes, color, alpha=1.0, lines=()):
    path = OUT_DIR / f"taskbar_{name}_{theme}.ico"
    render(shapes, color, alpha, lines).save(path, format="ICO", sizes=ICO_SIZES)
    return path


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for theme in ("dark", "light"):
        neutral, accent = NEUTRAL[theme], ACCENT[theme]
        save_ico("play", theme, PLAY, neutral)
        save_ico("pause", theme, PAUSE, neutral)
        save_ico("previous", theme, PREVIOUS, neutral)
        save_ico("next", theme, NEXT, neutral)
        save_ico("repeat_off", theme, REPEAT, neutral, REPEAT_OFF_ALPHA)
        save_ico("repeat_all", theme, REPEAT, accent)
        save_ico("repeat_one", theme, REPEAT + ONE, accent)
        save_ico("shuffle_off", theme, SHUFFLE_HEADS, neutral, REPEAT_OFF_ALPHA,
                 SHUFFLE_LINES)
        save_ico("shuffle_on", theme, SHUFFLE_HEADS, accent, 1.0, SHUFFLE_LINES)
    print(f"ok: {len(list(OUT_DIR.glob('taskbar_*.ico')))} icones em {OUT_DIR}")


if __name__ == "__main__":
    main()
