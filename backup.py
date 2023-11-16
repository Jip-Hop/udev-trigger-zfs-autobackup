import io
import sys
from contextlib import redirect_stdout
# from zfs_autobackup.ZfsAutobackup import *
from zfs_autobackup import cli
from typing import Optional
from log_util import Logging
from mail_util import mail, mail_error
from config_reader import AppConfig
import subprocess

# Backup function
def backup(device_label, config: AppConfig, logger: Logging):
    pool_config = config.pools.get(device_label, None)
    if pool_config is None:
        mail(f"Plugged in disk {device_label} that is matching configuration. You can unplug it again safely.",
             config.smtp, logger)
    else:
        mail(f"Plugged in disk {device_label} that is matching configuration:\n"+
             f"{pool_config}\n\n" + 
              "Starting the backup now. You will receive an email once the backup has compled and you can safely unplug the disk.",
             config.smtp, logger)

        try:
            logger.log(f"Importing pool {device_label}")
            result = import_pool(device_label, logger)
            if result.returncode != 0:
                mail_error(f"Failed to import pool. Backup not yet run.\n\nError:\n{result.stderr}", config.smtp, logger)
                return

            if pool_config.passphrase is not None and pool_config.passphrase:
                logger.log(f"Decrypting pool {device_label}")
                result = decrypt_pool(device_label, pool_config.passphrase, logger)
                if result.returncode != 0:
                    mail_error(f"Failed to decrypt pool. Backup not yet run.\n\nError:\n{result.stderr}", config.smtp, logger)
                    return

            logger.log(f"Starting ZFS-Autobackup for pool {device_label} with parameters:\n" +
                        "zfs-autobackup" + " ".join(pool_config.autobackup_parameters))
            captured_output = run_zfs_autobackup(pool_config.autobackup_parameters, logger)
            # Assuming run_zfs_autobackup returns a string, check if it indicates an error
            if "error" in captured_output.lower():
                if config.smtp.send_autobackup_output:
                    mail_error(f"ZFS autobackup error! Disk will not be exported automatically:\n\n{captured_output}", config.smtp, logger)
                else:
                    mail_error(f"ZFS autobackup error! Disk will not be exported automatically. Check logs for details.", config.smtp, logger)
                return
            else:
                logger.log(captured_output)
                

            logger.log(f"Setting pool {device_label} to read-only")
            result = set_pool_readonly(device_label, logger)
            if result.returncode != 0:
                mail_error(f"Failed to set pool readonly. Disk will not be exported automatically.\n\nError:\n{result.stderr}", config.smtp, logger)
                return

            logger.log(f"Exporting {device_label}")
            result = export_pool(device_label, logger)
            if result.returncode != 0:
                mail_error(f"Failed to export pool.\n\nError:\n{result.stderr}", config.smtp, logger)
                return

            if config.smtp.send_autobackup_output:
                mail(f"Backup finished. You can safely unplug the disk {device_label} now.\n\nZFS-Autobackup output:\n{captured_output}", config.smtp, logger)
            else:
                mail(f"Backup finished. You can safely unplug the disk {device_label} now.", config.smtp, logger)

        except Exception as e:
            mail_error(f"An unexpected error occurred. Backup mail have failed. Please investigate.\n\nError:\n{e}", config.smtp, logger)
        

def run_zfs_autobackup(args, logger: Logging) -> str:
    """
    Runs the ZfsAutobackup CLI with given arguments and captures its stdout output.

    :param args: List of command-line arguments to pass to ZfsAutobackup CLI.
    :return: The captured stdout output as a string.
    """
    # Backup the original sys.argv
    original_argv = sys.argv

    # Redirect standard output to capture it
    stdout_capture = io.StringIO()
    with redirect_stdout(stdout_capture):
        try:
            # Set sys.argv to the CLI tool's expected input
            sys.argv = ['zfs-autobackup'] + args
            # Call the CLI function
            cli()
        except SystemExit as e:
            # Handle the sys.exit call; could log or re-raise if needed
            pass
        finally:
            # Restore the original sys.argv
            sys.argv = original_argv

    # Return the captured output
    return stdout_capture.getvalue()

def import_pool(pool: str, logger: Logging) -> subprocess.CompletedProcess:
    return run_command(logger, ["zpool", "import", pool, "-N"])

def export_pool(pool: str, logger: Logging) -> subprocess.CompletedProcess:
    return run_command(logger, ["zpool", "export", pool])

def decrypt_pool(pool: str, passphrase: str, logger: Logging) -> subprocess.CompletedProcess:
    run_command(logger, ["zfs", "load-key", pool], input_data=passphrase)

def set_pool_readonly(pool: str, logger: Logging) -> subprocess.CompletedProcess:
    return run_command(logger, ["zfs", "set", "readonly=on", pool])

def run_command(logger: Logging, command, input_data=None) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(command, input=input_data, text=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        logger.error(f"An error occurred: {e}")
        return subprocess.CompletedProcess(e.cmd, e.returncode, stdout=e.output, stderr=e.stderr)
