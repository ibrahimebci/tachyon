#if TACHYON_CUDA
#include <iostream>

// clang-format off
#include "benchmark/ec/ec_util.h"
#include "benchmark/ec/simple_ec_benchmark_reporter.h"
#include "benchmark/msm/msm_config.h"
// clang-format on
#include "tachyon/base/time/time_interval.h"
#include "tachyon/device/gpu/cuda/scoped_memory.h"
#include "tachyon/device/gpu/gpu_enums.h"
#include "tachyon/device/gpu/gpu_logging.h"
#include "tachyon/device/gpu/scoped_async_memory.h"
#include "tachyon/device/gpu/scoped_mem_pool.h"
#include "tachyon/math/elliptic_curves/bn/bn254/g1_cuda.cu.h"
#include "tachyon/math/elliptic_curves/msm/variable_base_msm.h"
#include "tachyon/math/elliptic_curves/msm/variable_base_msm_cuda.cu.h"

namespace tachyon {

using namespace device;
using namespace math;

int RealMain(int argc, char** argv) {
  ECConfig config;
  if (!config.Parse(argc, argv)) {
    return 1;
  }

  bn254::G1AffinePointCuda::Curve::Init();
  bn254::G1AffinePoint::Curve::Init();
  VariableBaseMSMCuda<bn254::G1AffinePointCuda::Curve>::Setup();

  SimpleECBenchmarkReporter reporter(config.degrees());

  std::vector<uint64_t> point_nums = config.GetPointNums();

  std::cout << "Generating random points..." << std::endl;
  uint64_t max_point_num = point_nums.back();
  std::vector<bn254::G1AffinePoint> bases =
      CreateRandomBn254Points(max_point_num);
  std::vector<bn254::Fr> scalars = CreateRandomBn254Scalars(max_point_num);
  std::cout << "Generation completed" << std::endl;

  base::TimeInterval interval(base::TimeTicks::Now());
  std::vector<bn254::G1JacobianPoint> results_cpu;
  for (uint64_t point_num : point_nums) {
    auto bases_begin = bases.begin();
    auto scalars_begin = scalars.begin();
    results_cpu.push_back(VariableBaseMSM<bn254::G1AffinePoint>::MSM(
        bases_begin, bases_begin + point_num, scalars_begin,
        scalars_begin + point_num));
    auto duration = interval.GetTimeDelta();
    std::cout << "calculate:" << duration.InSecondsF() << std::endl;
    reporter.AddResult(duration.InSecondsF());
  }

  gpuError_t error = gpuDeviceReset();
  GPU_CHECK(error == gpuSuccess, error);
  gpuMemPoolProps props = {gpuMemAllocationTypePinned,
                           gpuMemHandleTypeNone,
                           {gpuMemLocationTypeDevice, 0}};
  gpu::ScopedMemPool mem_pool = gpu::CreateMemPool(&props);
  uint64_t mem_pool_threshold = std::numeric_limits<uint64_t>::max();
  error = gpuMemPoolSetAttribute(mem_pool.get(), gpuMemPoolAttrReleaseThreshold,
                                 &mem_pool_threshold);
  GPU_CHECK(error == gpuSuccess, error) << "Failed to gpuMemPoolSetAttribute()";

  gpu::ScopedDeviceMemory<bn254::G1AffinePointCuda> d_bases =
      gpu::Malloc<bn254::G1AffinePointCuda>(point_nums.back());
  gpu::ScopedDeviceMemory<bn254::FrCuda> d_scalars =
      gpu::Malloc<bn254::FrCuda>(point_nums.back());
  gpu::ScopedDeviceMemory<bn254::G1JacobianPointCuda> d_results =
      gpu::Malloc<bn254::G1JacobianPointCuda>(256);
  std::unique_ptr<bn254::G1JacobianPoint[]> u_results(
      new bn254::G1JacobianPoint[256]);

  gpu::ScopedStream stream = gpu::CreateStream();
  kernels::msm::ExecutionConfig<bn254::G1AffinePointCuda::Curve>
      execution_config;
  execution_config.mem_pool = mem_pool.get();
  execution_config.stream = stream.get();
  execution_config.bases = d_bases.get();
  execution_config.scalars = d_scalars.get();
  execution_config.results = d_results.get();

  std::vector<bn254::G1JacobianPoint> results_gpu;

  interval.Start();
  for (size_t i = 0; i < config.degrees().size(); ++i) {
    auto now = base::TimeTicks::Now();
    gpuMemcpy(d_bases.get(), bases.data(),
              sizeof(bn254::G1AffinePointCuda) * point_nums[i],
              gpuMemcpyHostToDevice);
    gpuMemcpy(d_scalars.get(), scalars.data(),
              sizeof(bn254::FrCuda) * point_nums[i], gpuMemcpyHostToDevice);
    std::cout << "host -> device:"
              << (base::TimeTicks::Now() - now).InSecondsF() << std::endl;
    execution_config.log_scalars_count = config.degrees()[i];

    now = base::TimeTicks::Now();
    error = VariableBaseMSMCuda<bn254::G1AffinePointCuda::Curve>::ExecuteAsync(
        execution_config);
    GPU_CHECK(error == gpuSuccess, error) << "Failed to ExecuteAsync()";
    error = gpuStreamSynchronize(stream.get());
    GPU_CHECK(error == gpuSuccess, error) << "Failed to gpuStreamSynchronize()";
    std::cout << "calculate:" << (base::TimeTicks::Now() - now).InSecondsF()
              << std::endl;

    now = base::TimeTicks::Now();
    gpuMemcpy(u_results.get(), execution_config.results,
              sizeof(bn254::G1JacobianPointCuda) * 256, gpuMemcpyDefault);
    std::cout << "device -> host:"
              << (base::TimeTicks::Now() - now).InSecondsF() << std::endl;
    bn254::G1JacobianPoint result = bn254::G1JacobianPoint::Zero();
    for (size_t i = 0; i < bn254::Fr::Config::kModulusBits; ++i) {
      size_t index = bn254::Fr::Config::kModulusBits - i - 1;
      bn254::G1JacobianPoint bucket = u_results[index];
      if (i == 0) {
        result = bucket;
      } else {
        result.DoubleInPlace();
        result += bucket;
      }
    }
    results_gpu.push_back(result);
    reporter.AddResult(interval.GetTimeDelta().InSecondsF());
  }

  CHECK(results_cpu == results_gpu) << "Result not matched";

  reporter.Show();

  return 0;
}

}  // namespace tachyon

int main(int argc, char** argv) { return tachyon::RealMain(argc, argv); }
#else
#include "tachyon/base/console/iostream.h"

int main(int argc, char **argv) {
  tachyon_cerr << "please build with --config cuda" << std::endl;
  return 1;
}
#endif  // TACHYON_CUDA