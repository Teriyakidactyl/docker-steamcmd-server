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
        self.assertEqual(len(build["include"]), 16)

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
        wine = next(item for item in build["include"] if item["compat_layer_id"] == "wine-staging-11.8" and item["architecture"] == "amd64")
        self.assertEqual(wine["tag_codename_arch"], "trixie_wine-staging_amd64")

    def test_manifest_architectures_match_compatibility_support(self):
        manifests = matrix.generate_manifest_matrix("refs/heads/main", "ghcr.io/example/base")
        proton = [item for item in manifests["include"] if "proton-" in item["target_tag_versioned"]]
        self.assertTrue(proton)
        self.assertTrue(all(item["architectures"] == ["amd64"] for item in proton))


if __name__ == "__main__":
    unittest.main()
