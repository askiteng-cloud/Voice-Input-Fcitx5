#pragma once

#include <fcitx/addonfactory.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>
#include <fcitx/event.h>
#include <fcitx/instance.h>
#include <fcitx-utils/eventloopinterface.h>

class SherpaBridge : public fcitx::AddonInstance {
public:
    SherpaBridge(fcitx::AddonManager *manager);
    ~SherpaBridge() override;

private:
    bool handleSocket(fcitx::EventSourceIO* source, int fd, fcitx::IOEventFlags flags);

    fcitx::AddonManager *manager_;
    std::unique_ptr<fcitx::EventSourceIO> socketEvent_;
    int sock_fd_;
};
