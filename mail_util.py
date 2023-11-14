import smtplib
import yaml
from email.message import EmailMessage
from log_util import Logging
from config_reader import SmtpConfig

# from config_reader import read_validate_config

# Load the configuration from the YAML file
# config, pools_lookup = read_validate_config('config.yaml')

# Enclose the mail sending logic in a function
def send_email(subject, body, config: SmtpConfig, logger: Logging):
    # Set the sender email and password
    # sender_email = config['smtp']['login']
    # password = config['smtp']['password']

    # Create the plain-text email
    message = EmailMessage()
    message.set_content(body)  # Set email body
    message['Subject'] = subject  # Set email subject
    message['From'] = config.login  # Set email from

    # SMTP server configuration
    # smtp_server = config['smtp']['server']
    # smtp_port = config['smtp']['port']

    # Send the email to all recipients
    message['To'] = config.recipients#['smtp']['recipients']  # Set current recipient

    # Send the email
    try:
        # Create an SMTP object and specify the server and the port
        with smtplib.SMTP(config.server, config.port) as server:
            server.starttls()  # Start TLS encryption
            server.login(config.login, config.password)  # Log in to the SMTP server
            server.send_message(message)  # Send the email
            logger.log(f"Email sent successfully to {config.recipients}!")
    except Exception as e:
        logger.error(f"Error sending email to {config.recipients}: {e}")

# Example usage
# send_email("Test Subject", "This is a test body of the email.")
