#pragma once

#include <QString>
#include <memory>

class CredentialStore;

// The executable supplies defaults. Explicit dependencies let integration tests
// run this SAME bootstrap without reading the user's vault or application log.
// There is no command-line, environment, QML or network override for these.
struct ClientApplicationOptions {
  std::shared_ptr<CredentialStore> credentialStore;
  QString logDirectory;
};

int runClientApplication(int argc, char *argv[],
                         ClientApplicationOptions options = {});
