#include "vendors/halo2/include/xor_shift_rng.h"

#include "tachyon/crypto/random/xor_shift/xor_shift_rng.h"

namespace tachyon::halo2_api {

class XORShiftRng::Impl {
 public:
  explicit Impl(std::array<uint8_t, 16> seed) {
    uint8_t seed_copy[16];
    memcpy(seed_copy, seed.data(), 16);
    rng_ = crypto::XORShiftRNG::FromSeed(seed_copy);
  }

  uint32_t NextUint32() { return rng_.NextUint32(); }

 private:
  crypto::XORShiftRNG rng_;
};

XORShiftRng::XORShiftRng(std::array<uint8_t, 16> seed)
    : impl_(new Impl(seed)) {}

uint32_t XORShiftRng::next_u32() { return impl_->NextUint32(); }

std::unique_ptr<XORShiftRng> new_xor_shift_rng(std::array<uint8_t, 16> seed) {
  return std::make_unique<XORShiftRng>(seed);
}

}  // namespace tachyon::halo2_api
