
#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <stdio.h>

#include "cuda_context.hpp"
#include "cuda_pointer.hpp"
#include "cuda_pointer_vector_utils.hpp"
#include "cuda_multi_dim_vector.hpp"
#include "cuda_pointer_thrust_utils.hpp"
#include "cuda_multi_dim_vector_thrust_utils.hpp"
#include "multi_dim_vector_with_memory.hpp"

#include "compile_time_differentiation_tests.hpp"
#include "experiments.hpp"

#include <thrust/functional.h>
#include <thrust/sort.h>
#include <assert.h>

#include <memory>
#include "multi_dim_vector.hpp"
#include "multi_dim_vector_iterator.hpp"
#include "multi_dim_vector_range.hpp"

cudaError_t addWithCuda(std::vector<int>& c, std::vector<int> const& a, std::vector<int> const& b);

__global__ void addKernel(aks::multi_dim_vector<int, 1> c, aks::multi_dim_vector<int const, 1> a, aks::multi_dim_vector<int const, 1> b)
{
    int i = threadIdx.x;
	int sum = 0;
	for (auto it = aks::begin(a, aks::token()), end = aks::end(a, aks::token()); it != end; ++it)
		sum += *it;
	for (auto const& x : aks::make_multi_dim_vector_range(b, aks::token()))
		sum += x;
    c(i) = a(i) + b(i) - sum;
}

__global__ void addKernel(aks::multi_dim_vector<int, 3> c, aks::multi_dim_vector<int const, 3> const a, aks::multi_dim_vector<int const, 3> const b)
{
	int const i = threadIdx.x;
	int const j = threadIdx.y;
	int const k = threadIdx.z;

	int sum = 0;
	for (auto it = aks::begin(a, aks::token(), j, k), end = aks::end(a, aks::token(), j, k); it != end; ++it)
		sum += *it;
	for (auto it = aks::begin(a, i, aks::token(), k), end = aks::end(a, i, aks::token(), k); it != end; ++it)
		sum += *it;
	for (auto const& x : aks::make_multi_dim_vector_range(b, i, j, aks::token()))
		sum += x;

	c(i, j, k) = sum;
}

void check2()
{
	compile_time_differentiation_tests();
	{
		aks::host_multi_dim_vector<int, 3> vec(3, 4, 5);
		auto view = vec.view();
		auto const& const_vec = vec;
		auto const_view = const_vec.view();
		printf("");
	}
	if(true)
	{  
		aks::cuda_context ctxt(aks::cuda_device(0));
		aks::host_multi_dim_vector<int, 3> host_vec(3, 4, 5);
		auto host_view = host_vec.view();
		auto m0 = host_view.max_dimension<0>();
		auto m1 = host_view.max_dimension<1>();
		auto m2 = host_view.max_dimension<2>();
		auto m00 = aks::get_max_dim<0>(host_view);
		auto m01 = aks::get_max_dim<1>(host_view);
		auto m02 = aks::get_max_dim<2>(host_view);
		for(size_t x=0; x<3; ++x)
			for (size_t y = 0; y<4; ++y)
				for (size_t z = 0; z < 5; ++z)
				{
					host_view(x, y, z) = x*4*5 + y*5 + z;
				}

		aks::cuda_multi_dim_vector<int, 3> vec = aks::to_device(host_vec);// (host_vec.view().data(), 3, 4, 5);
		aks::cuda_multi_dim_vector<int, 3> res(3, 4, 5);
		
		dim3 threadsPerBlock(3, 4, 5);
		{
			aks::cuda_sync_context sync_ctxt;
			addKernel<<< 1, threadsPerBlock >>>(res.view(), vec.view(), vec.cview());
		}

		//auto view = vec.view();
		//auto const& const_vec = vec;
		//auto const_view = const_vec.view();

		//auto tmp = aks::from_cuda_pointer(vec.m_data);

		//std::vector<int> ret(view.total_size());
		//vec.m_data.load(ret.data());

		aks::host_multi_dim_vector<int, 3> ret_vec(3, 4, 5);
		ret_vec << res;

		auto ret_vec2 = aks::to_host(res);
		
		printf("");
	}
}

int main()
{
	run_experiments();
	check2();

    //aks::cuda_context ctxt;
    
    std::vector<int> const a = { 1, 2, 3, 4, 5 };
    std::vector<int> const b = { 10, 20, 30, 40, 50 };
    std::vector<int> c;

    // Add vectors in parallel.
    cudaError_t cudaStatus = addWithCuda(c, a, b);
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "addWithCuda failed!");
        return 1;
    }

    printf("{1,2,3,4,5} + {10,20,30,40,50} = {%d,%d,%d,%d,%d}\n",
        c[0], c[1], c[2], c[3], c[4]);

    return 0;
}

// Helper function for using CUDA to add vectors in parallel.
cudaError_t addWithCuda2(std::vector<int>& c, std::vector<int> const& a, std::vector<int> const& b)
{
    using namespace aks;

    cuda_context ctxt(cuda_device(0));
    auto da = make_cuda_pointer(a);
    auto db = make_cuda_pointer(b);
    //cuda_pointer<int const> db(size, b);
    cuda_pointer<int> dc(a.size());
    //dc.deep_copy_from(db);
    auto const ma = make_multi_dim_vector(da.data(), da.size());
    auto const mb = make_multi_dim_vector(db.data(), da.size());
    auto mc = make_multi_dim_vector(dc.data(), da.size());

    {
        cuda_sync_context sync_ctxt;
        addKernel<<<1, a.size()>>>(mc, ma, mb);
    }

    thrust::transform(thrust_utils::begin(ma), thrust_utils::end(ma), thrust_utils::begin(mb), thrust_utils::begin(mc), thrust::plus<int>());

    printf("%d\n", thrust::reduce(thrust_utils::begin(ma), thrust_utils::end(ma), (int)0));
    printf("%d\n", thrust::reduce(thrust_utils::begin(mb), thrust_utils::end(mb), (int)0));
    printf("%d\n", thrust::reduce(thrust_utils::begin(mc), thrust_utils::end(mc), (int)0));

    thrust::transform(thrust_utils::begin(mc), thrust_utils::end(mc), thrust_utils::begin(mc), thrust::negate<int>());
    thrust::sort(thrust_utils::begin(mc), thrust_utils::end(mc));	

    c = from_cuda_pointer(dc);

    assert(!da.has_error_occurred() && !db.has_error_occurred() && !dc.has_error_occurred());

    //check();

    return last_status();

}

// Helper function for using CUDA to add vectors in parallel.
cudaError_t addWithCuda(std::vector<int>& c, std::vector<int> const& a, std::vector<int> const& b)
{
    aks::cuda_context ctxt(aks::cuda_device(0));
    aks::cuda_pointer<int const> da = aks::make_cuda_pointer(a);
    aks::cuda_pointer<int const> db = aks::make_cuda_pointer(b);      
    //aks::cuda_pointer<int const> db(size, b);
    aks::cuda_pointer<int> dc(a.size());
    //dc.deep_copy_from(db);
    aks::multi_dim_vector<int const, 1> const ma = aks::make_multi_dim_vector(da.data(), da.size());
    aks::multi_dim_vector<int const, 1> const mb = aks::make_multi_dim_vector(db.data(), da.size());
    aks::multi_dim_vector<int, 1> mc = aks::make_multi_dim_vector(dc.data(), da.size());

    {
        aks::cuda_sync_context sync_ctxt;
        addKernel <<<1, a.size()>>>(mc, ma, mb);
    }

	c = aks::from_cuda_pointer(dc);

    //thrust::device_vector<int> const tva = aks::to_thrust_device_vector(ma);
    //thrust::device_vector<int> const tvb = aks::to_thrust_device_vector(mb);
    //thrust::device_vector<int> tvc = aks::to_thrust_device_vector(mc);  

    thrust::transform(aks::thrust_utils::begin(ma), aks::thrust_utils::end(ma), aks::thrust_utils::begin(mb), aks::thrust_utils::begin(mc), thrust::plus<int>());

    printf("%d\n", thrust::reduce(aks::thrust_utils::begin(ma), aks::thrust_utils::end(ma), (int)0));
    printf("%d\n", thrust::reduce(aks::thrust_utils::begin(mb), aks::thrust_utils::end(mb), (int)0));
    printf("%d\n", thrust::reduce(aks::thrust_utils::begin(mc), aks::thrust_utils::end(mc), (int)0));

    thrust::transform(aks::thrust_utils::begin(mc), aks::thrust_utils::end(mc), aks::thrust_utils::begin(mc), thrust::negate<int>());
    thrust::sort(aks::thrust_utils::begin(mc), aks::thrust_utils::end(mc));

    c = aks::from_cuda_pointer(dc);

    assert(!da.has_error_occurred() && !db.has_error_occurred() && !dc.has_error_occurred());

    //check();

    return aks::last_status();
    
}
