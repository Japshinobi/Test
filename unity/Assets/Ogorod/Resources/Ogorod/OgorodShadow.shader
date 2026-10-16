// Shadows on the ground. The stencil lets every pixel be darkened only once,
// so overlapping shadows do not get darker (as in the browser version).
Shader "Ogorod/Shadow"
{
    Properties
    {
        _MainTex ("Atlas", 2D) = "white" {}
        _Color ("Shadow colour", Color) = (0.024, 0.063, 0.165, 0.34)
    }
    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Pass
        {
            ZWrite Off ZTest Always Cull Off
            Blend SrcAlpha OneMinusSrcAlpha
            Stencil { Ref 1 Comp NotEqual Pass Replace }
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            sampler2D _MainTex;
            fixed4 _Color;
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
            v2f vert (appdata_base v) { v2f o; o.pos = UnityObjectToClipPos(v.vertex); o.uv = v.texcoord.xy; return o; }
            fixed4 frag (v2f i) : SV_Target { clip(tex2D(_MainTex, i.uv).a - 0.5); return _Color; }
            ENDCG
        }
    }
}
