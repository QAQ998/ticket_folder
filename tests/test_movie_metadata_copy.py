from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
APP_FILES = [
    ROOT / "TicketWalletApp" / "Views" / "TicketSearchView.swift",
    ROOT / "TicketWalletApp" / "Views" / "MovieSearchView.swift",
    ROOT / "TicketWalletApp" / "Services" / "TMDBClient.swift",
]


class MovieMetadataCopyTests(unittest.TestCase):
    def test_copy_does_not_suggest_manual_movie_metadata_entry(self):
        forbidden = [
            "手动填写资料",
            "手动电影资料",
            "手动填写影片资料",
        ]
        for path in APP_FILES:
            content = path.read_text(encoding="utf-8")
            for phrase in forbidden:
                self.assertNotIn(phrase, content, f"{phrase} found in {path}")

    def test_copy_mentions_douban_first_metadata_flow(self):
        search_content = (ROOT / "TicketWalletApp" / "Views" / "TicketSearchView.swift").read_text(encoding="utf-8")
        settings_content = (ROOT / "TicketWalletApp" / "Views" / "RootTabView.swift").read_text(encoding="utf-8")
        self.assertIn("优先自动补全豆瓣信息", search_content)
        self.assertIn("豆瓣优先，TMDB 兜底", settings_content)


if __name__ == "__main__":
    unittest.main()
