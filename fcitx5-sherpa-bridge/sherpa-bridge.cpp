#include "sherpa-bridge.h"
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextmanager.h>
#include <fcitx/inputpanel.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <fcitx-utils/log.h>
#include <fcitx-utils/event.h>
#include <fcitx/text.h>

SherpaBridge::SherpaBridge(fcitx::AddonManager *manager)
    : manager_(manager), sock_fd_(-1) {
    
    sock_fd_ = socket(AF_UNIX, SOCK_DGRAM, 0);
    if (sock_fd_ < 0) {
        FCITX_ERROR() << "Failed to create unix datagram socket.";
        return;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    
    const char* home = getenv("HOME");
    std::string socket_path_str = std::string(home) + "/.fcitx5_sherpa.sock";
    const char* socket_path = socket_path_str.c_str();
    strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);
    
    unlink(socket_path);

    if (bind(sock_fd_, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        FCITX_ERROR() << "Failed to bind unix socket: " << socket_path;
        close(sock_fd_);
        sock_fd_ = -1;
        return;
    }

    socketEvent_ = manager_->instance()->eventLoop().addIOEvent(
        sock_fd_, fcitx::IOEventFlag::In,
        [this](fcitx::EventSourceIO* source, int fd, fcitx::IOEventFlags flags) {
            return this->handleSocket(source, fd, flags);
        });
        
    FCITX_INFO() << "Sherpa Bridge initialized.";
}

SherpaBridge::~SherpaBridge() {
    socketEvent_.reset();
    if (sock_fd_ >= 0) {
        close(sock_fd_);
        unlink("/tmp/fcitx5_sherpa.sock");
    }
}

bool SherpaBridge::handleSocket(fcitx::EventSourceIO*, int, fcitx::IOEventFlags flags) {
    if (!(flags & fcitx::IOEventFlag::In)) {
        return true;
    }

    char buf[4096];
    ssize_t n = recv(sock_fd_, buf, sizeof(buf) - 1, 0);
    if (n > 0) {
        buf[n] = '\0';
        std::string text(buf);
        FCITX_INFO() << "Sherpa Bridge received: " << text;
        
        auto* ic = manager_->instance()->inputContextManager().lastFocusedInputContext();
        if (ic) {
            FCITX_INFO() << "Sherpa Bridge: Found active input context.";
            if (text.find("COMMIT:") == 0) {
                std::string commitText = text.substr(7);
                FCITX_INFO() << "Sherpa Bridge: Committing: " << commitText;
                
                // Clear preedit state and notify client to avoid duplication in GTK apps like Mousepad
                ic->inputPanel().reset();
                ic->updatePreedit();
                
                ic->commitString(commitText);
                ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
            } else if (text.find("PREEDIT:") == 0) {
                std::string preeditText = text.substr(8);
                FCITX_INFO() << "Sherpa Bridge: Setting preedit: " << preeditText;
                fcitx::Text formatText(preeditText);
                ic->inputPanel().setPreedit(formatText);
                ic->inputPanel().setClientPreedit(formatText);
                ic->updatePreedit();
                ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
            } else {
                ic->commitString(text);
            }
        } else {
            FCITX_WARN() << "Sherpa Bridge: No focused input context found!";
        }
    }
    return true;
}

class SherpaBridgeFactory : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance *create(fcitx::AddonManager *manager) override {
        return new SherpaBridge(manager);
    }
};

FCITX_ADDON_FACTORY(SherpaBridgeFactory)
