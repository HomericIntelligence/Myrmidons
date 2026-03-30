cmake_minimum_required(VERSION 3.20)
project(hello_myrmidon CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)

FetchContent_Declare(
  nats_c
  GIT_REPOSITORY https://github.com/nats-io/nats.c.git
  GIT_TAG v3.9.1
  GIT_SHALLOW TRUE
)
set(NATS_BUILD_STREAMING OFF CACHE BOOL "" FORCE)
set(NATS_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(nats_c)

FetchContent_Declare(
  nlohmann_json
  GIT_REPOSITORY https://github.com/nlohmann/json.git
  GIT_TAG v3.11.3
  GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(nlohmann_json)

add_executable(hello_myrmidon main.cpp)
target_link_libraries(hello_myrmidon PRIVATE nats_static nlohmann_json::nlohmann_json)
