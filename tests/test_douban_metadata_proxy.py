from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKER = ROOT / "server" / "cloudflare-worker" / "douban-metadata-proxy.js"
README = ROOT / "server" / "cloudflare-worker" / "README.md"


def read(path):
    return path.read_text(encoding="utf-8")


class DoubanMetadataProxyTests(unittest.TestCase):
    def test_worker_exposes_app_contract(self):
        source = read(WORKER)
        self.assertIn('url.pathname !== "/movie/search"', source)
        self.assertIn("results: [movie]", source)
        for field in [
            "title",
            "original_title",
            "release_date",
            "directors",
            "runtime_minutes",
            "douban_rating",
            "poster_url",
        ]:
            self.assertIn(field, source)

    def test_worker_has_abuse_controls(self):
        source = read(WORKER)
        self.assertIn("MOVIE_PROXY_TOKEN", source)
        self.assertIn("METADATA_CACHE", source)
        self.assertIn("RATE_LIMIT_KV", source)
        self.assertIn("RATE_LIMIT_MAX_REQUESTS = 10", source)
        for status in ["403", "418", "429"]:
            self.assertIn(status, source)

    def test_docs_describe_no_direct_app_scraping_boundary(self):
        docs = read(README)
        self.assertIn("The iOS app does not call Douban pages directly.", docs)
        self.assertIn("does not retry or attempt to bypass protection", docs)
        self.assertIn("licensed data provider", docs)


if __name__ == "__main__":
    unittest.main()
