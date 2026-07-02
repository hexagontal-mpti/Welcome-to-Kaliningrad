from game.app import CountryballsApp


def main() -> None:
    app = CountryballsApp("config.json")
    app.run()


if __name__ == "__main__":
    main()
