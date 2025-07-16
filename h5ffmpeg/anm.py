import numpy as np
import os
import h5ffmpeg as hf
from h5ffmpeg.utils import compress_and_decompress
import matplotlib.pyplot as plt
from skimage import feature
from skimage.filters import threshold_otsu, gaussian
from skimage.metrics import structural_similarity as ssim
from scipy.ndimage import gaussian_filter, generic_filter
from scipy.fftpack import dct
from scipy.optimize import curve_fit
import warnings

warnings.filterwarnings("ignore")

def normalize(img):
    return img / np.max(img)

def analyze_content(img):
    img_norm = normalize(img)
    
    if img_norm.ndim == 3:
        mid_z = img_norm.shape[0] // 2
        img_analysis = img_norm[mid_z]
    else:
        img_analysis = img_norm
    
    try:
        thresh = threshold_otsu(img_analysis)
        binary = img_analysis > thresh
        structure_density = np.mean(binary)
    except:
        structure_density = np.sum(img_analysis > np.mean(img_analysis)) / img_analysis.size
    
    background = img_analysis * (1 - binary) if 'binary' in locals() else img_analysis * (img_analysis < np.percentile(img_analysis, 25))
    background_pixels = background[background > 0]
    background_uniformity = 1 - np.std(background_pixels) if len(background_pixels) > 0 else 0.5
    
    from scipy import ndimage
    gx = ndimage.sobel(img_analysis, axis=1)
    gy = ndimage.sobel(img_analysis, axis=0)
    gradient_mag = np.hypot(gx, gy)
    detail_level = np.percentile(gradient_mag / np.max(gradient_mag), 75)
    
    return {
        'structure_density': structure_density,
        'background_uniformity': background_uniformity,
        'detail_level': detail_level
    }

def extract_patches(img, num_samples=5, patch_size=(32, 128, 128)):
    z, h, w = img.shape
    patch_z, patch_h, patch_w = patch_size
    
    patch_z = min(patch_z, z)
    patch_h = min(patch_h, h)
    patch_w = min(patch_w, w)
    
    mid_z = z // 2
    analysis_slice = img[mid_z]
    
    edges = feature.canny(analysis_slice, sigma=1.5)
    texture = generic_filter(analysis_slice, np.std, size=7)
    
    detail_map_2d = edges * 2 + texture / np.max(texture)
    detail_map_2d = detail_map_2d / np.max(detail_map_2d)
    
    z_gradient = np.abs(np.diff(img, axis=0))
    z_variation = np.mean(z_gradient, axis=0)
    z_variation = z_variation / np.max(z_variation)
    
    detail_map_3d = detail_map_2d + z_variation
    detail_map_3d = detail_map_3d / np.max(detail_map_3d)
    
    high_detail = detail_map_3d > np.percentile(detail_map_3d, 75)
    
    patches = []
    high_detail_coords = np.argwhere(high_detail)
    np.random.shuffle(high_detail_coords)
    high_detail_samples = min(int(num_samples * 0.7), len(high_detail_coords))
    
    for i in range(high_detail_samples):
        if i < len(high_detail_coords):
            y, x = high_detail_coords[i]
            
            z_start = np.random.randint(0, max(1, z - patch_z + 1))
            y_start = min(max(0, y - patch_h//2), h - patch_h)
            x_start = min(max(0, x - patch_w//2), w - patch_w)
            
            patch = img[z_start:z_start+patch_z, y_start:y_start+patch_h, x_start:x_start+patch_w]
            patches.append(patch)
    
    remaining_samples = num_samples - len(patches)
    for _ in range(remaining_samples):
        z_start = np.random.randint(0, z - patch_z + 1)
        y_start = np.random.randint(0, h - patch_h + 1)
        x_start = np.random.randint(0, w - patch_w + 1)
        patch = img[z_start:z_start+patch_z, y_start:y_start+patch_h, x_start:x_start+patch_w]
        patches.append(patch)
    
    return np.stack(patches, axis=0)

def detect_blockiness(img, block_sizes=[8, 16]):
    img_norm = normalize(img)
    
    if img_norm.ndim == 4:
        total_score = 0
        for i in range(img_norm.shape[0]):
            patch = img_norm[i]
            mid_z = patch.shape[0] // 2
            channel = patch[mid_z]
            total_score += _detect_blockiness_single(channel, block_sizes)
        return total_score / img_norm.shape[0]
    
    elif img_norm.ndim == 3:
        mid_z = img_norm.shape[0] // 2
        channel = img_norm[mid_z]
    else:
        channel = img_norm
    
    return _detect_blockiness_single(channel, block_sizes)

def _detect_blockiness_single(channel, block_sizes):
    gx = np.abs(np.diff(channel, axis=1, prepend=channel[:, :1]))
    gy = np.abs(np.diff(channel, axis=0, prepend=channel[:1, :]))
    
    block_score = 0
    for block_size in block_sizes:
        h_pattern = np.mean(gx[:, block_size-1::block_size])
        h_non_pattern = np.mean(np.delete(gx, np.arange(block_size-1, gx.shape[1], block_size), axis=1))
        h_ratio = h_pattern / (h_non_pattern + 1e-8)
        
        v_pattern = np.mean(gy[block_size-1::block_size, :])
        v_non_pattern = np.mean(np.delete(gy, np.arange(block_size-1, gy.shape[0], block_size), axis=0))
        v_ratio = v_pattern / (v_non_pattern + 1e-8)
        
        block_score += max(0, h_ratio - 1.2) + max(0, v_ratio - 1.2)
    
    def dct_blockiness(img, block_size=8):
        h, w = img.shape
        score = 0
        
        for i in range(0, h-block_size, block_size):
            for j in range(0, w-block_size, block_size):
                block = img[i:i+block_size, j:j+block_size]
                dct_block = dct(dct(block.T, norm='ortho').T, norm='ortho')
                high_freq = np.abs(dct_block[4:, 4:])
                low_freq = np.abs(dct_block[:4, :4])
                
                if np.mean(high_freq) > 0.05 * np.mean(low_freq):
                    score += 1
        
        blocks_analyzed = ((h // block_size) * (w // block_size))
        return score / max(1, blocks_analyzed)
    
    dct_score = dct_blockiness(channel)
    
    smooth = gaussian(channel, sigma=0.5)
    diff = np.abs(channel - smooth)
    
    h_disc = np.sum(np.mean(diff[:, block_sizes[0]-1::block_sizes[0]], axis=1))
    v_disc = np.sum(np.mean(diff[block_sizes[0]-1::block_sizes[0], :], axis=0))
    
    h_disc /= channel.shape[0]
    v_disc /= channel.shape[1]
    
    struct_score = (h_disc + v_disc) / 2
    return 0.4 * block_score + 0.4 * dct_score + 0.2 * struct_score

def analyze_structure_preservation(original, compressed):
    if original.ndim == 4:
        boundary_scores = []
        detail_scores = []
        intensity_scores = []
        
        for i in range(original.shape[0]):
            orig_patch = original[i]
            comp_patch = compressed[i]
            mid_z = orig_patch.shape[0] // 2
            orig_analysis = orig_patch[mid_z]
            comp_analysis = comp_patch[mid_z]
            
            scores = _analyze_structure_single(orig_analysis, comp_analysis)
            boundary_scores.append(scores['boundary_preservation'])
            detail_scores.append(scores['detail_preservation'])
            intensity_scores.append(scores['intensity_preservation'])
        
        return {
            'boundary_preservation': np.mean(boundary_scores),
            'detail_preservation': np.mean(detail_scores),
            'intensity_preservation': np.mean(intensity_scores),
            'overall_quality': (np.mean(boundary_scores) + np.mean(detail_scores) + np.mean(intensity_scores)) / 3
        }
    
    if original.ndim == 3:
        mid_z = original.shape[0] // 2
        orig_analysis = original[mid_z]
        comp_analysis = compressed[mid_z]
    else:
        orig_analysis = original
        comp_analysis = compressed
    
    return _analyze_structure_single(orig_analysis, comp_analysis)

def _analyze_structure_single(orig_analysis, comp_analysis):
    orig_norm = orig_analysis / np.max(orig_analysis)
    comp_norm = comp_analysis / np.max(comp_analysis)
    
    edges_orig = feature.canny(orig_norm, sigma=1.0)
    edges_comp = feature.canny(comp_norm, sigma=1.0)
    
    true_positive = np.sum(edges_orig & edges_comp)
    false_negative = np.sum(edges_orig & ~edges_comp)
    false_positive = np.sum(~edges_orig & edges_comp)
    
    precision = true_positive / (true_positive + false_positive + 1e-10)
    recall = true_positive / (true_positive + false_negative + 1e-10)
    f1_boundary = 2 * (precision * recall) / (precision + recall + 1e-10)
    
    orig_smooth = gaussian_filter(orig_norm, sigma=2.0)
    comp_smooth = gaussian_filter(comp_norm, sigma=2.0)
    
    orig_detail = orig_norm - orig_smooth
    comp_detail = comp_norm - comp_smooth
    
    data_range = np.max(orig_detail) - np.min(orig_detail)
    if data_range <= 0:
        data_range = 1.0
    detail_ssim = ssim(orig_detail, comp_detail, data_range=data_range)
    
    try:
        thresh_orig = threshold_otsu(orig_norm)
        mask_orig = orig_norm > thresh_orig
    except:
        mask_orig = orig_norm > np.mean(orig_norm)
    
    def kl_divergence(p, q):
        p = p + 1e-10
        q = q + 1e-10
        p = p / np.sum(p)
        q = q / np.sum(q)
        return np.sum(p * np.log(p / q))
    
    hist_orig, bins = np.histogram(orig_norm[mask_orig], bins=50, density=True)
    hist_comp, _ = np.histogram(comp_norm[mask_orig], bins=bins, density=True)
    
    if len(hist_orig) > 0 and len(hist_comp) > 0 and np.sum(hist_orig) > 0 and np.sum(hist_comp) > 0:
        kl_div = (kl_divergence(hist_orig, hist_comp) + kl_divergence(hist_comp, hist_orig)) / 2
        intensity_similarity = np.exp(-kl_div)
    else:
        intensity_similarity = 0.5
    
    return {
        'boundary_preservation': f1_boundary,
        'detail_preservation': detail_ssim,
        'intensity_preservation': intensity_similarity,
        'overall_quality': (f1_boundary + detail_ssim + intensity_similarity) / 3
    }

def plot_results(grains, blockiness, perceptual, compression, combined, best_grain):
    plt.figure(figsize=(14, 10))
    gs = plt.GridSpec(2, 2, height_ratios=[1, 1])
    
    ax1 = plt.subplot(gs[0, 0])
    ax1.plot(grains, blockiness, 'ro-', linewidth=2, markersize=6)
    ax1.set_ylabel('Blockiness Score\n(lower is better)', fontsize=10)
    ax1.set_title('Artifact Detection', fontsize=12)
    ax1.grid(True, alpha=0.3)
    
    ax2 = plt.subplot(gs[0, 1])
    ax2.plot(grains, perceptual, 'go-', linewidth=2, markersize=6)
    ax2.set_ylabel('Perceptual Quality\n(higher is better)', fontsize=10)
    ax2.set_title('Structure Preservation', fontsize=12)
    ax2.grid(True, alpha=0.3)
    
    ax3 = plt.subplot(gs[1, 0])
    ax3.plot(grains, combined, 'bo-', linewidth=2, markersize=6)
    ax3.axvline(x=best_grain, color='black', linestyle='--', linewidth=2, 
                label=f'Best grain: {best_grain}')
    ax3.set_xlabel('Film Grain Parameter', fontsize=10)
    ax3.set_ylabel('Combined Score\n(higher is better)', fontsize=10)
    ax3.set_title('Overall Quality', fontsize=12)
    ax3.grid(True, alpha=0.3)
    ax3.legend(fontsize=10)
    
    ax4 = plt.subplot(gs[1, 1])
    ax4.plot(grains, compression, 'mo-', linewidth=2, markersize=6)
    ax4.axvline(x=best_grain, color='black', linestyle='--', linewidth=2)
    ax4.set_xlabel('Film Grain Parameter', fontsize=10)
    ax4.set_ylabel('Compression Ratio\n(higher is better)', fontsize=10)
    ax4.set_title('Storage Efficiency', fontsize=12)
    ax4.grid(True, alpha=0.3)
    
    ax1.annotate(f'Min: {min(blockiness):.3f}', 
                xy=(grains[np.argmin(blockiness)], min(blockiness)),
                xytext=(grains[np.argmin(blockiness)]+2, min(blockiness)*1.1),
                arrowprops=dict(facecolor='black', shrink=0.05, width=1),
                fontsize=9)
    
    ax2.annotate(f'Max: {max(perceptual):.3f}', 
                xy=(grains[np.argmax(perceptual)], max(perceptual)),
                xytext=(grains[np.argmax(perceptual)]+2, max(perceptual)*0.95),
                arrowprops=dict(facecolor='black', shrink=0.05, width=1),
                fontsize=9)
    
    os.makedirs('tmp', exist_ok=True)
    plt.tight_layout()
    plt.savefig('tmp/grain_optimization.png', dpi=150)
    plt.close()

def film_grain_optimizer(img=None, num_samples=5, quality_focus='artifacts', crf=30, th=0.015, norm=False, plot=False):
    def fn(x, a, b, c):
        return a * np.exp(-b * x) + c
    def fit_fn(x, popt):
        return popt[0] * np.exp(-popt[1] * x) + popt[2]
    def derivative(x, popt):
        return -popt[0] * popt[1] * np.exp(-popt[1] * x)
    
    if img is None:
        raise ValueError("img must be provided")
    
    print(f"Analyzing image of shape {img.shape}...")
    
    content_info = analyze_content(img)
    print("\nContent Analysis:")
    for key, value in content_info.items():
        print(f"  - {key}: {value:.3f}")
    
    print(f"\nExtracting {num_samples} representative patches...")
    img_patches = extract_patches(img, num_samples=num_samples)
    
    if content_info['detail_level'] > 0.7:
        grain_range = range(0, 31, 3)
        print("High detail content detected - using fine parameter sweep")
    elif content_info['background_uniformity'] > 0.8:
        grain_range = range(5, 51, 5)
        print("Uniform background detected - optimizing to prevent banding")
    else:
        grain_range = range(0, 51, 5)
        print("Mixed content detected - using standard parameter range")
    
    print(f"Testing grain parameters: {list(grain_range)}")
    
    original_patches = img_patches.copy()
    params = [hf.svtav1(film_grain=grain, crf=crf, norm=norm) for grain in grain_range]
    
    blockiness_scores = []
    compression_ratios = []
    perceptual_scores = []
    structure_scores = []
    
    raw_blockiness = detect_blockiness(original_patches)
    blockiness_scores.append(raw_blockiness)
    print(f"Raw blockiness score: {raw_blockiness:.4f}")

    if quality_focus == 'artifacts':
        weights = {'blockiness': 0.9, 'perceptual': 0.05, 'structure': 0.05}
        print("\nOptimizing for artifacts similarity")
    elif quality_focus == 'structures':
        weights = {'blockiness': 0.3, 'perceptual': 0.3, 'structure': 0.4}
        print("\nOptimizing for structure preservation")
    elif quality_focus == 'background':
        weights = {'blockiness': 0.5, 'perceptual': 0.4, 'structure': 0.1}
        print("\nOptimizing for artifact reduction")
    else:
        weights = {'blockiness': 0.4, 'perceptual': 0.3, 'structure': 0.3}
        print("\nUsing balanced approach")
    
    print("\nTesting parameters:")
    print(f"{'Grain':<6} {'Score':<8} {'Blockiness':<12} {'SSIM':<12} {'Structure':<12} {'Ratio':<8}")
    print("-" * 50)
    
    for i, param in enumerate(params):
        all_decom_patches = []
        total_cs_ratio = 0
        
        for j in range(img_patches.shape[0]):
            patch = img_patches[j]
            decom_patch, cs_ratio, _, _, _ = compress_and_decompress(patch, param)
            all_decom_patches.append(decom_patch)
            total_cs_ratio += cs_ratio
        
        decom_data = np.stack(all_decom_patches, axis=0)
        avg_cs_ratio = total_cs_ratio / img_patches.shape[0]
        compression_ratios.append(avg_cs_ratio)
        
        block_score = detect_blockiness(decom_data)
        blockiness_scores.append(block_score)

        original_patches = original_patches.astype(np.float32)
        decom_data = decom_data.astype(np.float32)
        
        if original_patches.ndim == 4:
            ssim_scores = []
            for j in range(original_patches.shape[0]):
                orig_patch = original_patches[j]
                comp_patch = decom_data[j]
                mid_z = orig_patch.shape[0] // 2
                ssim_score = ssim(orig_patch[mid_z], comp_patch[mid_z], data_range=np.amax(orig_patch[mid_z])-np.amin(orig_patch[mid_z]))
                ssim_scores.append(ssim_score)
            ssim_score = np.mean(ssim_scores)
        elif original_patches.ndim == 3:
            mid_z = original_patches.shape[0] // 2
            ssim_score = ssim(original_patches[mid_z], decom_data[mid_z], data_range=np.amax(original_patches[mid_z])-np.amin(original_patches[mid_z]))
        else:
            ssim_score = ssim(original_patches, decom_data, data_range=np.amax(original_patches)-np.amin(original_patches))
        
        perceptual_scores.append(ssim_score)
        
        structure_metrics = analyze_structure_preservation(original_patches, decom_data)
        structure_score = structure_metrics['overall_quality']
        structure_scores.append(structure_score)
    
    norm_blockiness = [score/blockiness_scores[0] for score in blockiness_scores[1:]]
    
    combined_scores = []
    for i in range(len(grain_range)):
        blockiness_component = weights['blockiness'] * (1 / (1 + abs(norm_blockiness[i] - 1)))
        score = (blockiness_component + 
                 weights['perceptual'] * perceptual_scores[i] +
                 weights['structure'] * structure_scores[i])
        combined_scores.append(score)

        print(f"{grain_range[i]:<6} {score:<8.2f} {blockiness_scores[i+1]:<12.4f} {perceptual_scores[i]:<12.4f} "
              f"{structure_scores[i]:<12.4f} {compression_ratios[i]:<8.2f}")
    
    popt, _ = curve_fit(fn, grain_range, 1 / np.array(combined_scores))
    best_grain = np.argwhere(np.abs(derivative(range(51), popt)) < th)
    if len(best_grain) > 0:
        best_grain = best_grain[0][0]
    else:
        best_grain = 5
    
    if plot:
        plot_results(grain_range, blockiness_scores[1:], perceptual_scores, 
                    compression_ratios, combined_scores, best_grain)
    
    print(f"\nOptimal film grain parameter: {best_grain}")
    
    return best_grain, {
        'content_analysis': content_info,
        'grain_range': list(grain_range),
        'blockiness_scores': blockiness_scores[1:],
        'perceptual_scores': perceptual_scores,
        'structure_scores': structure_scores,
        'compression_ratios': compression_ratios,
        'combined_scores': combined_scores
    }
