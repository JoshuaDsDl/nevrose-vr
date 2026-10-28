# -*- coding: utf-8 -*-
"""Génère un tableau encadré (GLB compatible Godot) à partir d'un PNG.

Usage : python make_framed_painting.py [image_source.png] [sortie.glb]
Sans argument : tableau_royesque.png -> tableau_royesque_framed.glb (dossier du script).
"""
import os
import sys
from PIL import Image
import numpy as np
import trimesh
from trimesh.visual.material import PBRMaterial

DOSSIER = os.path.dirname(os.path.abspath(__file__))
if len(sys.argv) >= 2:
    SRC = sys.argv[1]
else:
    SRC = os.path.join(DOSSIER, "tableau_royesque.png")
if len(sys.argv) >= 3:
    OUT = sys.argv[2]
else:
    base = os.path.splitext(os.path.basename(SRC))[0]
    OUT = os.path.join(os.path.dirname(os.path.abspath(SRC)), base + "_framed.glb")

# --- Image : aplatir l'alpha sur fond blanc (RGB) ---
im = Image.open(SRC).convert("RGBA")
fond = Image.new("RGBA", im.size, (255, 255, 255, 255))
im = Image.alpha_composite(fond, im).convert("RGB")

px_w, px_h = im.size
ratio = px_w / px_h

# --- Dimensions (mètres) ---
H = 0.84                 # hauteur de la toile
W = H * ratio            # largeur de la toile (~1.12 m)
BAR = 0.055              # largeur du cadre
DEPTH = 0.045            # profondeur du cadre
TOILE_Z = 0.004          # la toile est légèrement en retrait du bord avant du cadre
BACK_T = 0.006           # épaisseur du panneau arrière

scene = trimesh.Scene()

# --- Toile (quad texturé) ---
# UV : origine glTF en haut à gauche ; trimesh gère la convention.
verts = np.array([
    [-W/2, -H/2, TOILE_Z],
    [ W/2, -H/2, TOILE_Z],
    [ W/2,  H/2, TOILE_Z],
    [-W/2,  H/2, TOILE_Z],
], dtype=np.float64)
# attention : Godot/glTF = Y up ; trimesh exporte tel quel. On reste en XY plan, Z avant.
faces = np.array([[0, 1, 2], [0, 2, 3]])
# trimesh convertit les UV (origine bas-gauche) vers la convention glTF (haut-gauche)
# en inversant V à l'export : on fournit donc des UV "OpenGL" (0,0 = bas-gauche).
uv = np.array([[0, 0], [1, 0], [1, 1], [0, 1]], dtype=np.float64)
toile = trimesh.Trimesh(vertices=verts, faces=faces, process=False)
toile.visual = trimesh.visual.TextureVisuals(uv=uv, material=PBRMaterial(baseColorTexture=im, roughnessFactor=0.85, metallicFactor=0.0))
scene.add_geometry(toile, node_name="Toile", geom_name="Toile")

# Toile vue de l'arrière : quad dupliqué à l'envers (le matériau reste visible des deux côtés,
# Godot cull les faces arrière par défaut). UV identiques pour que l'image ne soit pas miroir
# quand on la voit de dos.
faces_ar = faces[:, ::-1]
toile_ar = trimesh.Trimesh(vertices=verts, faces=faces_ar, process=False)
toile_ar.visual = trimesh.visual.TextureVisuals(uv=uv, material=PBRMaterial(baseColorTexture=im, roughnessFactor=0.85, metallicFactor=0.0))
scene.add_geometry(toile_ar, node_name="Toile_Arriere", geom_name="Toile_Arriere")

# --- Cadre : 4 barres + fin liseré intérieur ---
or_dore = np.array([0.72, 0.55, 0.20, 1.0])   # doré
or_sombre = np.array([0.45, 0.32, 0.10, 1.0]) # liseré plus foncé

def barre(lx, ly, lz, cx, cy, cz, coul, nom):
    b = trimesh.creation.box(extents=(lx, ly, lz))
    b.apply_translation((cx, cy, cz))
    b.visual = trimesh.visual.ColorVisuals()
    b.visual.vertex_colors = np.tile((coul[:3] * 255).astype(np.uint8), (len(b.vertices), 1))
    m = trimesh.visual.material.PBRMaterial(baseColorFactor=coul.tolist(), roughnessFactor=0.35, metallicFactor=0.8)
    b.visual.material = m
    scene.add_geometry(b, node_name=nom, geom_name=nom)
    return b

extW, extH = W + 2*BAR, H + 2*BAR
z_cadre = TOILE_Z + DEPTH/2 - 0.002  # bord avant du cadre dépasse légèrement la toile
barre(extW, BAR, DEPTH, 0,  H/2 + BAR/2, z_cadre, or_dore, "Cadre_Haut")
barre(extW, BAR, DEPTH, 0, -H/2 - BAR/2, z_cadre, or_dore, "Cadre_Bas")
barre(BAR, H, DEPTH,  W/2 + BAR/2, 0, z_cadre, or_dore, "Cadre_Droit")
barre(BAR, H, DEPTH, -W/2 - BAR/2, 0, z_cadre, or_dore, "Cadre_Gauche")

# Liseré intérieur fin
LIS = 0.012
z_lis = TOILE_Z + 0.006
barre(W + 2*LIS, LIS, 0.008, 0,  H/2 + LIS/2, z_lis, or_sombre, "Liseret_Haut")
barre(W + 2*LIS, LIS, 0.008, 0, -H/2 - LIS/2, z_lis, or_sombre, "Liseret_Bas")
barre(LIS, H, 0.008,  W/2 + LIS/2, 0, z_lis, or_sombre, "Liseret_Droit")
barre(LIS, H, 0.008, -W/2 - LIS/2, 0, z_lis, or_sombre, "Liseret_Gauche")

# --- Dos : panneau sombre ---
dos = trimesh.creation.box(extents=(extW, extH, BACK_T))
# Dos reculé : derrière la face arrière du cadre (z_cadre - DEPTH/2), avec 2 mm de jeu,
# sinon sa face avant se confond avec le plan de la toile (z-fighting).
dos.apply_translation((0, 0, z_cadre - DEPTH/2 - BACK_T/2 - 0.002))
dos.visual = trimesh.visual.ColorVisuals()
dos.visual.material = trimesh.visual.material.PBRMaterial(
    baseColorFactor=[0.12, 0.09, 0.06, 1.0], roughnessFactor=0.9, metallicFactor=0.0)
scene.add_geometry(dos, node_name="Dos", geom_name="Dos")

# --- Export GLB (texture embarquée) ---
scene.export(OUT)
print("Exporté :", OUT)

# --- Vérification : rechargement ---
chk = trimesh.load(OUT, force="scene")
print("Nœuds :", sorted(chk.graph.nodes_geometry))
print("Geoms :", {k: v.faces.shape[0] for k, v in chk.geometry.items()})
taille = os.path.getsize(OUT)
print(f"Taille : {taille/1024:.0f} Ko")
print(f"Toile : {W:.3f} m x {H:.3f} m, cadre total : {extW:.3f} x {extH:.3f} m")
