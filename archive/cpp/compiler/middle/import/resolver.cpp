#include "resolver.hpp"
#include <filesystem>
#include <stdexcept>

namespace fs = std::filesystem;

namespace k {

ImportResolver::ImportResolver(const std::string &root) : rootDir(root) {}

std::string ImportResolver::resolve(const ImportDecl &imp) const {
  fs::path p = rootDir;

  // Build path: backend.core → backend/core.k
  for (const auto &part : imp.path) {
    p /= part;
  }

  p += ".k";

  if (!fs::exists(p)) {
    throw std::runtime_error("Import not found: " + p.string());
  }

  return p.string();
}

}