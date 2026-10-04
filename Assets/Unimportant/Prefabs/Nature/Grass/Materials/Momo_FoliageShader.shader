// Foliage shader ported from an Amplify Shader Editor surface shader to URP.
//
// The original was "#pragma surface surf StandardCustom", which emits ForwardBase/ForwardAdd
// passes that URP never executes, so nothing rendered. This is a hand-written URP replacement.
//
// Property names, ranges and defaults are unchanged so the ten existing materials keep every
// value they already have. Feature toggles keep their original keyword names too.
//
// Behaviour notes where the original was quirky, preserved deliberately:
//   * The wind graph subtracted mul(unity_WorldToObject, float4(cameraPos, 0)).w from the swayed
//     position. For any affine transform that .w is always 0, so it was a no-op and is omitted.
//   * With tinting enabled the original blended the texture over the gradient using a Multiply
//     blend whose opacity input was left at 0, which resolves to the gradient alone -- the
//     texture drops out entirely. Reproduced as-is; see MomoSurface below.
Shader "Assets/Momo_FoliageShader"
{
    Properties
    {
        [NoScaleOffset] _BaseTexture("Base Texture", 2D) = "white" {}
        [ToggleUI] _CUSTOMCOLORSTINTING("CUSTOM COLORS  TINTING", Float) = 0
        [HDR] _TopColor("Top Color", Color) = (0,0.2178235,1,1)
        [HDR] _GroundColor("Ground Color", Color) = (1,0,0,1)
        [HDR] _Gradient("Gradient", Range( 0 , 10)) = 1.4
        _GradientPower("Gradient Power", Range( 0 , 10)) = 1
        _LeavesThickness("Leaves Thickness", Range( 0.1 , 0.95)) = 0.5
        _Smoothness("Smoothness", Range( 0 , 1)) = 0
        [ToggleOff] _SpecularHighlights("Specular Highlights", Float) = 1.0

        [Toggle(_TRANSLUCENCYONOFF_ON)] _TRANSLUCENCYONOFF("TRANSLUCENCY ON/OFF", Float) = 1
        [Header(Translucency)]
        _Translucency("Strength", Range( 0 , 50)) = 1
        _TransNormalDistortion("Normal Distortion", Range( 0 , 1)) = 0.1
        _TransScattering("Scaterring Falloff", Range( 1 , 50)) = 2
        _TransDirect("Direct", Range( 0 , 1)) = 1
        _TransAmbient("Ambient", Range( 0 , 1)) = 0.2
        _TransShadow("Shadow", Range( 0 , 1)) = 0.9

        [Toggle(_CUSTOMWIND_ON)] _CUSTOMWIND("CUSTOM WIND", Float) = 1
        [HideInInspector] _MaskClipValue("Mask Clip Value", Range( 0 , 1)) = 0.5
        _WindMovement("Wind Movement", Range( 0 , 10)) = 0.5
        _WindDensity("Wind Density", Range( 0 , 5)) = 3.3
        _WindStrength("Wind Strength", Range( 0 , 1)) = 0.3

        [Toggle(_SNOWONOFF_ON)] _SNOWONOFF("SNOW ON/OFF", Float) = 0
        _SnowGradient("Snow Gradient", Range( 0 , 1)) = 0.83
        _SnowCoverage("Snow Coverage", Range( 0 , 1)) = 0.45
        _SnowAmount("Snow Amount", Range( 0 , 1)) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "TransparentCutout"
            "Queue" = "Geometry"
            "RenderPipeline" = "UniversalPipeline"
            "IgnoreProjector" = "True"
        }

        Cull Off
        LOD 300

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/LODCrossFade.hlsl"
        // URP's Shadows.hlsl calls LerpWhiteTo but does not include the header that defines it.
        // URP's own shaders get it indirectly through SurfaceInput.hlsl; this shader does not use
        // SurfaceInput.hlsl (it would declare _BaseMap and friends that we have no use for), so
        // pull in just the header that actually provides it.
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _TopColor;
            float4 _GroundColor;
            float _Gradient;
            float _GradientPower;
            float _CUSTOMCOLORSTINTING;
            float _LeavesThickness;
            float _MaskClipValue;
            float _Smoothness;
            float _SpecularHighlights;
            float _TRANSLUCENCYONOFF;
            float _Translucency;
            float _TransNormalDistortion;
            float _TransScattering;
            float _TransDirect;
            float _TransAmbient;
            float _TransShadow;
            float _CUSTOMWIND;
            float _WindMovement;
            float _WindDensity;
            float _WindStrength;
            float _SNOWONOFF;
            float _SnowGradient;
            float _SnowCoverage;
            float _SnowAmount;
        CBUFFER_END

        TEXTURE2D(_BaseTexture);
        SAMPLER(sampler_BaseTexture);

        // 2D simplex noise, carried over verbatim from the generated shader. Prefixed to avoid
        // colliding with anything in the URP shader library.
        float3 MomoMod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
        float2 MomoMod289(float2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
        float3 MomoPermute(float3 x) { return MomoMod289(((x * 34.0) + 1.0) * x); }

        float MomoSNoise(float2 v)
        {
            const float4 C = float4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
            float2 i = floor(v + dot(v, C.yy));
            float2 x0 = v - i + dot(i, C.xx);
            float2 i1;
            i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
            float4 x12 = x0.xyxy + C.xxzz;
            x12.xy -= i1;
            i = MomoMod289(i);
            float3 p = MomoPermute(MomoPermute(i.y + float3(0.0, i1.y, 1.0)) + i.x + float3(0.0, i1.x, 1.0));
            float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
            m = m * m;
            m = m * m;
            float3 x = 2.0 * frac(p * C.www) - 1.0;
            float3 h = abs(x) - 0.5;
            float3 ox = floor(x + 0.5);
            float3 a0 = x - ox;
            m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
            float3 g;
            g.x = a0.x * x0.x + h.x * x0.y;
            g.yz = a0.yz * x12.xz + h.yz * x12.yw;
            return 130.0 * dot(m, g);
        }

        // Sways the vertex along object-space X, scaled by height so the base stays anchored.
        // Must be applied identically in every pass or shadows and depth detach from the visible
        // geometry.
        float3 MomoApplyWind(float3 positionOS)
        {
        #ifdef _CUSTOMWIND_ON
            float noise = MomoSNoise((positionOS + (_Time.y * _WindMovement)).xy * _WindDensity);
            noise = noise * 0.5 + 0.5;
            float3 swayed = float3(((noise - 0.5) / 10.0) * _WindStrength + positionOS.x,
                                   positionOS.y,
                                   positionOS.z);
            return lerp(positionOS, swayed, positionOS.y * 2.0);
        #else
            return positionOS;
        #endif
        }

        // Leaves are cut out where the texture alpha falls below the thickness threshold.
        float MomoAlphaMask(float textureAlpha)
        {
            return 1.0 - step(textureAlpha, 1.0 - _LeavesThickness);
        }

        void MomoSurface(float2 uv, float3 positionWS, float3 normalWS,
                         out half3 albedo, out half3 translucencyColor, out half alphaMask)
        {
            half4 tex = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, uv);

            // max() guards pow against a negative base; uv.y and _Gradient are both >= 0 in
            // practice, so this only silences the compiler.
            float gradientT = clamp(pow(max(uv.y * _Gradient, 0.0), _GradientPower), 0.0, 1.0);
            half4 gradient = lerp(_GroundColor, _TopColor, gradientT);

            // See the header note: the original Multiply blend ran at opacity 0, so the tinted
            // branch is the gradient alone and the texture is discarded.
            half4 color = (_CUSTOMCOLORSTINTING > 0.5) ? gradient : tex;

            albedo = color.rgb;

        #ifdef _SNOWONOFF_ON
            float3 viewDirWS = normalize(GetCameraPositionWS() - positionWS);
            float fresnel = 0.11 + (1.0 - dot(normalWS, viewDirWS));
            float coverage = smoothstep(0.0, _SnowGradient,
                                        (1.0 - (uv.y * 0.65)) + (-1.0 + _SnowCoverage * 2.0));
            albedo = ((_SnowAmount * 10.0) * fresnel * coverage).xxx;
        #endif

        #ifdef _TRANSLUCENCYONOFF_ON
            translucencyColor = color.rgb;
        #else
            translucencyColor = half3(0, 0, 0);
        #endif

            alphaMask = MomoAlphaMask(tex.a);
        }
        ENDHLSL

        // ------------------------------------------------------------------
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            ZWrite On
            Blend One Zero

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ForwardVertex
            #pragma fragment ForwardFragment

            #pragma shader_feature_local_vertex _CUSTOMWIND_ON
            #pragma shader_feature_local_fragment _SNOWONOFF_ON
            #pragma shader_feature_local_fragment _TRANSLUCENCYONOFF_ON
            #pragma shader_feature_local_fragment _SPECULARHIGHLIGHTS_OFF

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _LIGHT_LAYERS
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DYNAMICLIGHTMAP_ON
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                float2 staticLightmapUV : TEXCOORD1;
                float2 dynamicLightmapUV : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                half3 normalWS : TEXCOORD2;
                half4 fogFactorAndVertexLight : TEXCOORD3;
                DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 4);
            #ifdef DYNAMICLIGHTMAP_ON
                float2 dynamicLightmapUV : TEXCOORD5;
            #endif
            #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                float4 shadowCoord : TEXCOORD6;
            #endif
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings ForwardVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                float3 positionOS = MomoApplyWind(input.positionOS.xyz);
                VertexPositionInputs positionInputs = GetVertexPositionInputs(positionOS);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);

                output.positionCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = normalInputs.normalWS;
                output.uv = input.uv;

                half3 vertexLight = VertexLighting(positionInputs.positionWS, normalInputs.normalWS);
                half fogFactor = ComputeFogFactor(positionInputs.positionCS.z);
                output.fogFactorAndVertexLight = half4(fogFactor, vertexLight);

                OUTPUT_LIGHTMAP_UV(input.staticLightmapUV, unity_LightmapST, output.staticLightmapUV);
            #ifdef DYNAMICLIGHTMAP_ON
                output.dynamicLightmapUV = input.dynamicLightmapUV.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
            #endif
                OUTPUT_SH(output.normalWS.xyz, output.vertexSH);

            #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                output.shadowCoord = GetShadowCoord(positionInputs);
            #endif

                return output;
            }

            half4 ForwardFragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float3 normalWS = normalize(input.normalWS);

                half3 albedo;
                half3 translucencyColor;
                half alphaMask;
                MomoSurface(input.uv, input.positionWS, normalWS, albedo, translucencyColor, alphaMask);
                clip(alphaMask - _MaskClipValue);

            #ifdef LOD_FADE_CROSSFADE
                LODFadeCrossFade(input.positionCS);
            #endif

                InputData inputData = (InputData)0;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS = SafeNormalize(GetWorldSpaceViewDir(input.positionWS));
            #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                inputData.shadowCoord = input.shadowCoord;
            #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
                inputData.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
            #else
                inputData.shadowCoord = float4(0, 0, 0, 0);
            #endif
                inputData.fogCoord = InitializeInputDataFog(float4(input.positionWS, 1.0), input.fogFactorAndVertexLight.x);
                inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
            #if defined(DYNAMICLIGHTMAP_ON)
                inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.dynamicLightmapUV, input.vertexSH, normalWS);
            #else
                inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, normalWS);
            #endif
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
                inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);

                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = albedo;
                surfaceData.metallic = 0.0;
                surfaceData.specular = half3(0, 0, 0);
                surfaceData.smoothness = _Smoothness;
                surfaceData.occlusion = 1.0;
                surfaceData.emission = half3(0, 0, 0);
                surfaceData.alpha = 1.0;
                surfaceData.normalTS = half3(0, 0, 1);
                surfaceData.clearCoatMask = 0.0;
                surfaceData.clearCoatSmoothness = 0.0;

                half4 color = UniversalFragmentPBR(inputData, surfaceData);

            #ifdef _TRANSLUCENCYONOFF_ON
                // Mirrors the original LightingStandardCustom: light wrapping around thin leaves,
                // where _TransShadow decides how much shadowing dims the effect.
                Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, inputData.shadowMask);
                half3 attenuated = mainLight.color * (mainLight.distanceAttenuation * mainLight.shadowAttenuation);
                half3 lightAtten = lerp(mainLight.color, attenuated, _TransShadow);

                half3 distortedLightDir = mainLight.direction + normalWS * _TransNormalDistortion;
                half transVdotL = pow(saturate(dot(inputData.viewDirectionWS, -distortedLightDir)), _TransScattering);
                half3 translucency = lightAtten
                                   * (transVdotL * _TransDirect + inputData.bakedGI * _TransAmbient)
                                   * translucencyColor;

                color.rgb += albedo * translucency * _Translucency;
            #endif

                color.rgb = MixFog(color.rgb, inputData.fogCoord);
                color.a = 1.0;
                return color;
            }
            ENDHLSL
        }

        // ------------------------------------------------------------------
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ShadowVertex
            #pragma fragment ShadowFragment

            #pragma shader_feature_local_vertex _CUSTOMWIND_ON
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #pragma multi_compile_instancing
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings ShadowVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                float3 positionOS = MomoApplyWind(input.positionOS.xyz);
                float3 positionWS = TransformObjectToWorld(positionOS);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif

                output.positionCS = positionCS;
                output.uv = input.uv;
                return output;
            }

            half4 ShadowFragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                half alpha = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, input.uv).a;
                clip(MomoAlphaMask(alpha) - _MaskClipValue);
            #ifdef LOD_FADE_CROSSFADE
                LODFadeCrossFade(input.positionCS);
            #endif
                return 0;
            }
            ENDHLSL
        }

        // ------------------------------------------------------------------
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex DepthVertex
            #pragma fragment DepthFragment

            #pragma shader_feature_local_vertex _CUSTOMWIND_ON
            #pragma multi_compile_instancing
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings DepthVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                output.positionCS = TransformObjectToHClip(MomoApplyWind(input.positionOS.xyz));
                output.uv = input.uv;
                return output;
            }

            half4 DepthFragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                half alpha = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, input.uv).a;
                clip(MomoAlphaMask(alpha) - _MaskClipValue);
            #ifdef LOD_FADE_CROSSFADE
                LODFadeCrossFade(input.positionCS);
            #endif
                return 0;
            }
            ENDHLSL
        }

        // ------------------------------------------------------------------
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }

            ZWrite On

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            #pragma shader_feature_local_vertex _CUSTOMWIND_ON
            #pragma multi_compile_instancing
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                half3 normalWS : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings DepthNormalsVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                float3 positionOS = MomoApplyWind(input.positionOS.xyz);
                output.positionCS = TransformObjectToHClip(positionOS);
                output.normalWS = GetVertexNormalInputs(input.normalOS).normalWS;
                output.uv = input.uv;
                return output;
            }

            half4 DepthNormalsFragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                half alpha = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, input.uv).a;
                clip(MomoAlphaMask(alpha) - _MaskClipValue);
            #ifdef LOD_FADE_CROSSFADE
                LODFadeCrossFade(input.positionCS);
            #endif
                return half4(NormalizeNormalPerPixel(input.normalWS), 0.0);
            }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}
