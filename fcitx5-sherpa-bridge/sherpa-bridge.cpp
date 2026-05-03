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
    strncpy(addr.sun_path, "/tmp/fcitx5_sherpa.sock", sizeof(addr.sun_path) - 1);
    
    unlink("/tmp/fcitx5_sherpa.sock");

    if (bind(sock_fd_, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        FCITX_ERROR() << "Failed to bind unix socket.";
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
        
        auto* ic = manager_->instance()->inputContextManager().lastFocusedInputContext();
        if (ic) {
            if (text.find("COMMIT:") == 0) {
                ic->commitString(text.substr(7));
                ic->inputPanel().reset();
                ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
            } else if (text.find("PREEDIT:") == 0) {
                fcitx::Text formatText(text.substr(8));
                ic->inputPanel().setPreedit(formatText);
                ic->inputPanel().setClientPreedit(formatText);
                ic->updatePreedit();
                ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
            } else {
                ic->commitString(text);
            }
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
