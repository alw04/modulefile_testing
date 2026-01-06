from __future__ import annotations

import argparse
import tarfile
import zipfile
from contextlib import closing
from pathlib import Path
from shutil import rmtree
from subprocess import run

import pycurl
import yaml
from jinja2 import Environment, FileSystemLoader


class Installer:
    def __init__(self, name: str, version: str | None) -> None:
        self.root_path = Path.cwd()
        self.config = self._load_config()

        self.name = name
        self._load_recipe(version)

    def _load_config(self) -> dict:
        with open(self.root_path / "config.yml") as f:
            return yaml.safe_load(f)

    def _load_recipe(self, version: str | None) -> None:
        with open(self.root_path / "recipes" / f"{self.name}.yml") as f:
            raw = yaml.safe_load(f)

        defaults = raw.get("defaults", {})
        versions = raw.get("versions", {})

        if not versions:
            raise ValueError(f"Recipe '{self.name}' has no versions defined")

        if version:
            selected = version
        elif "default_version" in defaults:
            selected = defaults["default_version"]
        else:
            selected = next(iter(versions))

        if selected not in versions:
            raise ValueError(f"Version '{selected}' not found in recipe '{self.name}'")

        self.version = selected
        self.recipe = {**defaults, **versions[selected]}

    def _download(self) -> Path:
        url = self.recipe["url"]
        filename = Path(url).name

        download_path = Path(self.config["download_path"]) / self.name / self.version / filename
        download_path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = download_path.with_suffix(download_path.suffix + ".part")

        if download_path.exists():
            return download_path

        download_path.unlink(missing_ok=True)
        tmp_path.unlink(missing_ok=True)
        try:
            with open(tmp_path, "wb") as f, closing(pycurl.Curl()) as c:
                c.setopt(pycurl.URL, url)
                c.setopt(pycurl.WRITEDATA, f)
                c.setopt(pycurl.FOLLOWLOCATION, True)
                c.setopt(pycurl.FAILONERROR, True)
                c.perform()
        except pycurl.error as e:
            tmp_path.unlink(missing_ok=True)
            raise RuntimeError(f"Download failed: {url}") from e

        tmp_path.replace(download_path)
        return download_path

    def _extract(self, archive_path: Path) -> Path:
        extract_dir = Path(self.config["build_path"]) / self.name / self.version
        tmp_dir = extract_dir.with_name(extract_dir.name + ".part")
        marker = ".extracted"

        if (extract_dir / marker).exists():
            return extract_dir

        if extract_dir.exists():
            rmtree(extract_dir)

        if tmp_dir.exists():
            rmtree(tmp_dir)

        tmp_dir.mkdir(parents=True)

        if tarfile.is_tarfile(archive_path):
            with tarfile.open(archive_path) as t:
                t.extractall(tmp_dir, members=self._get_tar_members_stripped(t, strip=1))
        elif zipfile.is_zipfile(archive_path):
            with zipfile.ZipFile(archive_path) as z:
                z.extractall(tmp_dir)
        else:
            raise ValueError(f"Unsupported archive type: {archive_path}")

        (tmp_dir / marker).touch()
        tmp_dir.replace(extract_dir)
        return extract_dir

    # https://stackoverflow.com/a/67314242
    def _get_tar_members_stripped(self, tar, strip=1):
        for member in tar.getmembers():
            member.path = member.path.split("/", strip)[-1]
            yield member

    def _is_archive(self, path: Path) -> bool:
        return any((tarfile.is_tarfile(path), zipfile.is_zipfile(path)))

    def fetch(self) -> Path:
        path = self._download()

        if self._is_archive(path):
            path = self._extract(path)

        return path

    def build(self, source_dir: Path) -> Path:
        install_path = Path(self.config["install_path"]) / self.name / self.version
        tmp_path = install_path.with_name(install_path.name + ".part")
        marker = ".built"

        if (install_path / marker).exists():
            return install_path

        if install_path.exists():
            rmtree(install_path)

        if tmp_path.exists():
            rmtree(tmp_path)

        tmp_path.mkdir(parents=True)
        if self.recipe["build_system"] == "autotools":
            run([f"{source_dir}/configure", f"--prefix={tmp_path}"], cwd=source_dir)
            run(["make"], cwd=source_dir)
            run(["make", "install"], cwd=source_dir)
        else:
            raise ValueError(f"Unsupported build system: '{self.recipe['build_system']}'")

        (tmp_path / marker).touch()
        tmp_path.replace(install_path)
        return install_path

    def generate_modulefile(self) -> Path:
        env = Environment(loader=FileSystemLoader("module_utils/installer/templates"))
        template = env.get_template("lmod-template.j2")

        modulefile_dir = Path(self.config["modulefile_path"]) / self.name
        modulefile_dir.mkdir(parents=True, exist_ok=True)
        modulefile_path = modulefile_dir / f"{self.version}.lua"

        content = template.render(
            name=self.name,
            version=self.version,
            lmod_template_path=self.config["lmod_template_path"],
        )
        modulefile_path.write_text(content)

        return modulefile_path


def parse_args():
    parser = argparse.ArgumentParser(prog="installer")
    parser.add_argument("name", type=str, help="Software name")
    parser.add_argument("version", type=str, nargs="?", help="Software version")

    return parser.parse_args()


def main():
    args = parse_args()
    installer = Installer(args.name, args.version)
    source_dir = installer.fetch()
    installer.build(source_dir)
    installer.generate_modulefile()


if __name__ == "__main__":
    main()
