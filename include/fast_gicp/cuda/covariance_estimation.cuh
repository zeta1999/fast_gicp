#ifndef FAST_GICP_CUDA_COVARIANCE_ESTIMATION_CUH
#define FAST_GICP_CUDA_COVARIANCE_ESTIMATION_CUH

#include <Eigen/Core>
#include <Eigen/Geometry>

#include <cublas_v2.h>
#include <thrust/sequence.h>
#include <thrust/host_vector.h>
#include <thrust/device_vector.h>

namespace fast_gicp {

namespace {
  struct covariance_estimation_kernel {
    covariance_estimation_kernel(const thrust::device_vector<Eigen::Vector3f>& points, int k, const thrust::device_vector<int>& k_neighbors, thrust::device_vector<Eigen::Matrix3f>& covariances)
        : k(k), points_ptr(points.data()), k_neighbors_ptr(k_neighbors.data()), covariances_ptr(covariances.data()) {}

    __host__ __device__ void operator()(int idx) const {
      // target points buffer & nn output buffer
      const Eigen::Vector3f* points = thrust::raw_pointer_cast(points_ptr);
      const int* k_neighbors = thrust::raw_pointer_cast(k_neighbors_ptr) + idx * k;
      Eigen::Matrix3f* cov = thrust::raw_pointer_cast(covariances_ptr) + idx;

      Eigen::Vector3f mean(0.0f, 0.0f, 0.0f);
      cov->setZero();
      for(int i = 0; i < k; i++) {
        const auto& pt = points[k_neighbors[i]];
        mean += pt;
        (*cov) += pt * pt.transpose();
      }
      mean /= k;
      (*cov) = (*cov) / k - mean * mean.transpose();

      // I know double precision floats make gpu slow...
      float lambda = 1e-3;
      Eigen::Matrix3f C_ = (*cov) + lambda * Eigen::Matrix3f::Identity();
      Eigen::Matrix3d C = C_.cast<double>();
      Eigen::Matrix3d C_inv = C.inverse();
      Eigen::Matrix3d C_norm = (C_inv / C_inv.norm()).inverse();
      (*cov) = C_norm.cast<float>();
    }

    const int k;
    thrust::device_ptr<const Eigen::Vector3f> points_ptr;
    thrust::device_ptr<const int> k_neighbors_ptr;

    thrust::device_ptr<Eigen::Matrix3f> covariances_ptr;
  };
}

static void covariance_estimation(const thrust::device_vector<Eigen::Vector3f>& points, int k, const thrust::device_vector<int>& k_neighbors, thrust::device_vector<Eigen::Matrix3f>& covariances) {
  thrust::device_vector<int> d_indices(points.size());
  thrust::sequence(d_indices.begin(), d_indices.end());

  covariances.resize(points.size());
  thrust::for_each(d_indices.begin(), d_indices.end(), covariance_estimation_kernel(points, k, k_neighbors, covariances));
}

}

#endif