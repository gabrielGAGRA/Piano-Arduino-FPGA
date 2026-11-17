#!/usr/bin/env python3
"""
Testes unitarios para persistencia de historico do dashboard_pc.py
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

# Permite importar dashboard_pc a partir da pasta dashboard/
sys_path = Path(__file__).resolve().parent.parent
if str(sys_path) not in sys.path:
    sys.path.insert(0, str(sys_path))

import dashboard_pc


class TestHistoricoDashboard(unittest.TestCase):

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.history_file = Path(self.temp_dir.name) / "test_historico.json"

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_salvar_e_carregar_historico_basico(self):
        hist = dashboard_pc.carregar_historico(self.history_file)
        self.assertEqual(hist, {})

        hist = dashboard_pc.registrar_execucao(
            musica_id=6,
            acertos=7,
            erros=1,
            score=87,
            historico=hist,
            history_file=self.history_file
        )

        recarregado = dashboard_pc.carregar_historico(self.history_file)
        self.assertIn("6", recarregado)
        self.assertEqual(len(recarregado["6"]["execucoes"]), 1)
        self.assertEqual(recarregado["6"]["execucoes"][0]["score"], 87)
        self.assertEqual(recarregado["6"]["nome"], "Do Re Mi Fa")

    def test_limite_de_10_execucoes_por_musica(self):
        hist = {}
        for i in range(15):
            hist = dashboard_pc.registrar_execucao(
                musica_id=4,
                acertos=40 + i,
                erros=i,
                score=50 + i,
                historico=hist,
                history_file=self.history_file
            )

        recarregado = dashboard_pc.carregar_historico(self.history_file)
        execucoes = recarregado["4"]["execucoes"]
        self.assertEqual(len(execucoes), 10)
        # As 10 ultimas devem ser i = 5 ate i = 14
        self.assertEqual(execucoes[0]["score"], 55)
        self.assertEqual(execucoes[-1]["score"], 64)

    def test_independencia_entre_musicas(self):
        hist = {}
        # 12 execucoes na musica 4
        for i in range(12):
            hist = dashboard_pc.registrar_execucao(
                musica_id=4,
                acertos=i,
                erros=0,
                score=i * 5,
                historico=hist,
                history_file=self.history_file
            )

        # 3 execucoes na musica 6
        for j in range(3):
            hist = dashboard_pc.registrar_execucao(
                musica_id=6,
                acertos=j,
                erros=1,
                score=70 + j,
                historico=hist,
                history_file=self.history_file
            )

        recarregado = dashboard_pc.carregar_historico(self.history_file)
        self.assertEqual(len(recarregado["4"]["execucoes"]), 10)
        self.assertEqual(len(recarregado["6"]["execucoes"]), 3)

    def test_catalogo_43_musicas_sincronizado(self):
        self.assertEqual(len(dashboard_pc.NOMES_MUSICAS), 43)
        self.assertEqual(dashboard_pc.NOMES_MUSICAS[4], "Clair de Lune")
        self.assertEqual(dashboard_pc.NOMES_MUSICAS[6], "Do Re Mi Fa")
        self.assertEqual(dashboard_pc.NOMES_MUSICAS[18], "Jump Up Super Star")
        self.assertEqual(dashboard_pc.NOMES_MUSICAS[27], "New Donk City")
        self.assertEqual(dashboard_pc.NOMES_MUSICAS[40], "Wii Sports")
        self.assertEqual(dashboard_pc.NOMES_MUSICAS[41], "Zelda (Lost Woods)")
        self.assertEqual(dashboard_pc.NOMES_MUSICAS[42], "Musica Gravada pelo Usuario")


if __name__ == "__main__":
    unittest.main()
