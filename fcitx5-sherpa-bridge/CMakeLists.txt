cmake_minimum_required(VERSION 3.10)
project(fcitx5-sherpa-bridge)

find_package(ECM 1.0.0 REQUIRED)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH} ${CMAKE_MODULE_PATH})

find_package(Fcitx5Core 5.1.0 REQUIRED)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(sherpa-bridge MODULE sherpa-bridge.cpp)
set_target_properties(sherpa-bridge PROPERTIES PREFIX "")

target_link_libraries(sherpa-bridge Fcitx5::Core)

configure_file(sherpa-bridge.conf.in sherpa-bridge.conf @ONLY)

install(TARGETS sherpa-bridge DESTINATION "lib/fcitx5")
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/sherpa-bridge.conf" DESTINATION "share/fcitx5/addon")
