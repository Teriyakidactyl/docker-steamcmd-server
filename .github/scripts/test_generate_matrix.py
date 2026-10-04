import importlib.util
import pathlib
import unittest

MODULE_PATH = pathlib.Path(__file__).with_name("generate_matrix.py")
SPEC = importlib.util.spec_from_file_location("generate_matrix", MODULE_PATH)
matrix = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(matrix)


class MatrixTests(unittest.TestCase):
    def test_main_matrix_has_expected_size(self):
        build = matrix.generate_build_matrix("refs/heads/main", "ghcr.io/example/base")
        self.assertEqual(len(build["include"]), 15)

    def test_proton_is_amd64_only(self):
        build = matrix.generate_build_matrix("refs/heads/main", "ghcr.io/example/base")
        proton = [item for item in build["include"] if item["compat_layer_type"] == "proton"]
        self.assertTrue(proton)
        self.assertEqual({item["architecture"] for item in proton}, {"amd64"})

    def test_dev_suffix_precedes_architecture(self):
        build = matrix.generate_build_matrix("refs/heads/dev", "ghcr.io/example/base")
        self.assertTrue(all("_dev_" in item["tag_versioned_arch"] for item in build["include"]))

    def test_codename_aliases_are_stable(self):
        build = matrix.generate_build_matrix("refs/heads/main", "ghcr.io/example/base")
        wine = next(item for item in build["include"] if item["compat_layer_id"] == "wine-staging-11.19" and item["architecture"] == "amd64")
        self.assertEqual(wine["tag_codename_arch"], "trixie_wine-staging_amd64")

    def test_manifest_architectures_match_compatibility_support(self):
        manifests = matrix.generate_manifest_matrix("refs/heads/main", "ghcr.io/example/base")
        proton = [item for item in manifests["include"] if "proton-" in item["target_tag_versioned"]]
        self.assertTrue(proton)
        self.assertTrue(all(item["architectures"] == ["amd64"] for item in proton))

    def test_staging_wine_tracks_available_debian_packages(self):
        build = matrix.generate_build_matrix("refs/heads/main", "ghcr.io/example/base")
        staging = {
            (item["debian_codename"], item["architecture"]): item["wine_version_arg"]
            for item in build["include"]
            if item["compat_layer_type"] == "wine"
            and item["wine_branch_arg"] == "staging"
        }
        self.assertEqual(staging[("trixie", "amd64")], "11.19")
        self.assertEqual(staging[("trixie", "arm64")], "11.19")
        self.assertEqual(staging[("bookworm", "amd64")], "11.10")
        self.assertEqual(staging[("bookworm", "arm64")], "11.10")

    def test_current_proton_support(self):
        build = matrix.generate_build_matrix("refs/heads/main", "ghcr.io/example/base")
        proton = [
            item for item in build["include"]
            if item["compat_layer_type"] == "proton"
        ]
        versions_by_base = {
            codename: {
                item["proton_version_arg"]
                for item in proton
                if item["debian_codename"] == codename
            }
            for codename in {"trixie", "bookworm"}
        }
        self.assertEqual(versions_by_base["trixie"], {"11.7", "10.34"})
        self.assertEqual(versions_by_base["bookworm"], {"10.34"})

        manifests = matrix.generate_manifest_matrix("refs/heads/main", "ghcr.io/example/base")
        targets = {item["target_tag_versioned"] for item in manifests["include"]}
        self.assertTrue(any("trixie-20260421-slim_proton-11.7" in target for target in targets))
        self.assertFalse(any("bookworm-20260421-slim_proton-11.7" in target for target in targets))

    def test_arm64_uses_current_emulator_bundle(self):
        build = matrix.generate_build_matrix("refs/heads/main", "ghcr.io/example/base")
        arm64 = [item for item in build["include"] if item["architecture"] == "arm64"]
        self.assertTrue(arm64)
        self.assertTrue(all(item["box64_version_arg"] == "0.4.5" for item in arm64))
        self.assertTrue(all(item["box86_version_arg"] == "0.3.9" for item in arm64))
        self.assertTrue(all("f5ffcd0" in item["box64_deb_url_arg"] for item in arm64))
        self.assertTrue(all("7dec081" in item["box86_deb_url_arg"] for item in arm64))


if __name__ == "__main__":
    unittest.main()
