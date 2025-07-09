import pytest
import sys
from pathlib import Path

import seed_env.cli

def test_cli_prints_help_on_no_args(monkeypatch, capsys):
    # Simulate no arguments
    monkeypatch.setattr(sys, "argv", ["seed_env/cli.py"])
    with pytest.raises(SystemExit):
        seed_env.cli.main()
    captured = capsys.readouterr()
    assert "usage" in captured.out.lower() or "usage" in captured.err.lower()

def test_cli_error_on_missing_required(monkeypatch, capsys):
    # Simulate missing required arguments
    monkeypatch.setattr(sys, "argv", ["seed_env/cli.py", "--seed-project", "jax"])
    with pytest.raises(SystemExit):
        seed_env.cli.main()
    captured = capsys.readouterr()
    assert "error" in captured.out.lower() or "error" in captured.err.lower()

def test_cli_local_project(monkeypatch, tmp_path, mocker):
    # Simulate local project path
    requirements = tmp_path / "requirements.txt"
    requirements.write_text("foo==1.2.3\n")
    monkeypatch.setattr(sys, "argv", [
        "seed_env/cli.py",
        "--local-requirements", str(tmp_path),
        "--seed-project", "jax",
        "--python-version", "3.12"
    ])
    # Mock EnvironmentSeeder and its method
    mock_seeder = mocker.patch("seed_env.cli.EnvironmentSeeder")
    instance = mock_seeder.return_value
    instance.seed_environment.return_value = None
    seed_env.cli.main()
    assert instance.seed_environment.called

def test_cli_remote_project(monkeypatch, mocker):
    # Simulate remote repo
    monkeypatch.setattr(sys, "argv", [
        "seed_env/cli.py",
        "--host-repo", "org/repo",
        "--host-requirements", "requirements.txt",
        "--host-commit", "abc123",
        "--seed-project", "jax",
        "--python-version", "3.12"
    ])
    # Mock EnvironmentSeeder and its method
    mock_seeder = mocker.patch("seed_env.cli.EnvironmentSeeder")
    instance = mock_seeder.return_value
    instance.seed_environment.return_value = None
    seed_env.cli.main()
    assert instance.seed_environment.called
