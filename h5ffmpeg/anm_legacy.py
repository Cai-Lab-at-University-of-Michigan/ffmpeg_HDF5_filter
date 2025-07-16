import numpy as np
import os
import h5ffmpeg as hf
from h5ffmpeg.utils import compress_and_decompress
import matplotlib.pyplot as plt
from skimage import feature
from skimage.filters import threshold_otsu, gaussian
from skimage.metrics import structural_similarity as ssim
from scipy.ndimage import gaussian_filter, generic_filter
from scipy.optimize import curve_fit
from skimage import feature, draw
from PIL import Image, ImageChops
from skimage.transform import probabilistic_hough_line
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

def detect_blockiness(img):
    img_norm = np.array(normalize(img) * 255, dtype=np.uint8)
    
    if img_norm.ndim == 4:
        total_score = 0
        for i in range(img_norm.shape[0]):
            patch = img_norm[i]
            mid_z = patch.shape[0] // 2
            channel = patch[mid_z]
            total_score += _detect_blockiness_single(channel)
        return total_score / img_norm.shape[0]
    
    elif img_norm.ndim == 3:
        mid_z = img_norm.shape[0] // 2
        channel = img_norm[mid_z]
    else:
        channel = img_norm
    
    return _detect_blockiness_single(channel)

def _detect_blockiness_single(img):
    block_score = 0
    for im in img:
        im = np.array(normalize(im) * 255, dtype=np.uint8)
        im = Image.fromarray(im)
        im = ImageChops.subtract(im, im.transform(im.size, Image.Transform.AFFINE, (1,0,1,0,1,1)))
        im = np.asarray(im)

        im_zeros = np.zeros_like(im, np.uint8)
        # vertical and horizontal lines
        lines = probabilistic_hough_line(im, threshold=4, line_length=10, line_gap=0, theta=np.array([-np.pi/2, 0]))
        for line in lines:
            p0, p1 = line
            rr, cc = draw.line(p0[1], p0[0], p1[1], p1[0])
            im_zeros[rr, cc] = 1
        block_score += np.sum(im_zeros)
    
    return block_score

def film_grain_optimizer(img=None, num_samples=5, crf=15, th=0.015, norm=False):
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
    
    raw_blockiness = detect_blockiness(original_patches)
    blockiness_scores.append(raw_blockiness)
    print(f"Raw blockiness score: {raw_blockiness:.4f}")
    
    print("\nTesting parameters:")
    print(f"{'Grain':<6} {'Blockiness':<12} {'Ratio':<8}")
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
        
        print(f"{grain_range[i]:<6} {block_score:<12.4f} {avg_cs_ratio:<8.2f}")
    

    blockiness_scores = np.array(blockiness_scores[1:])
    popt, _ = curve_fit(fn, grain_range, np.log(blockiness_scores))

    best_grain = np.argwhere(np.abs(derivative(range(51), popt)) < th)
    if len(best_grain) > 0:
        best_grain = best_grain[0][0]
    else:
        best_grain = 5

    return best_grain