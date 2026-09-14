from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from django.core.management.base import BaseCommand

from licensing.signing import b64url


class Command(BaseCommand):
    help = (
        "Generate an Ed25519 keypair for signing license authorizations.\n"
        "Store the private key only in the server environment. Embed the public "
        "key in the macOS app."
    )

    def add_arguments(self, parser):
        parser.add_argument("--key-id", default="dev-1")

    def handle(self, *args, **options):
        private_key = Ed25519PrivateKey.generate()
        seed = private_key.private_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PrivateFormat.Raw,
            encryption_algorithm=serialization.NoEncryption(),
        )
        public_raw = private_key.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )
        pem = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        ).decode("ascii")

        self.stdout.write(f"LICENSE_SIGNING_KEY_ID={options['key_id']}")
        self.stdout.write(f"LICENSE_SIGNING_PRIVATE_KEY={b64url(seed)}")
        self.stdout.write("")
        self.stdout.write("# Public key (base64url, raw 32 bytes) — embed in the app:")
        self.stdout.write(b64url(public_raw))
        self.stdout.write("")
        self.stdout.write("# PEM form of the private key (server only):")
        self.stdout.write(pem)
