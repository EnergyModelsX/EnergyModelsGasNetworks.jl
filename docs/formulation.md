# Pooling Problem Formulation (Multi-commodity flow formulation)

$$min z = \sum_{(i,j) \in L^{trans}} C_{(i,j)} f_{(i,j)}$$

1. Capacity constraints for `TransmissionMode` (EMGeography)
$$f^{out}_{tm} \leq b_{tm}, \ \ \  tm \in M$$

$$f^{out}_{tm} \geq 0, \ \ \  tm \in M$$

$$f^{out}_{tm} = f^{in}_{tm} - f^{loss}_{tm}, \ \ tm \in M$$

$$f^{loss}_{tm} = loss \cdot f^{in}_{tm}, \ \ tm \in M$$

2. Balance equation in `Areas` and `GeoAvailability` (EMGeography + EMBase)
$$e_{a,p} = \sum_{tm' \in M^{+}_a | p \in P_a} f^{out}_{tm'} - \sum_{tm \in M^{+}_a | p_{tm} = p} f^{in}_{tm}, \ \  a \in A, p \in P_a$$
$$f^{in}_{n,p} = f^{out}_{n,p} - e_{a,p}, \ \  a \in A, p \in P_a, n \in G_a$$
...

3. Constraints for tracking the proportion of the flow in $tm$ from different sources (EMPooling)

For sources outside the area from $tm$ $ \in A^{+}_{tm}$
$$y^{s}_{tm} f^{in}_{tm} = \sum_{tm' \in M^{+}_{tm}} y^{s}_{tm'} f^{out}_{tm'}, \ \ \  tm \in M, s \in S_{tm} \setminus \{s \in S_{a} : a \in A^{+}_{tm}\}$$

where $y^{s}_{tm'} = 0$ if source $s$ not linked with $tm'$.

For sources inside the area from $tm$ $ \in A^{+}_{tm}$
$$y^{s}_{tm} f^{in}_{tm} = l^{out}_{s}, \ \ \  tm \in M, s \in S_{tm} \cap \{s \in S_{a} : a \in A^{+}_{tm}\}$$

4. Bound product constraints, limiting the proportion of blended component arriving to a $A^{t}$. Note that all the `TransmissioMode`arriving to the area must carry the same blended product.
$$\sum_{tm \in M^{+}_a} \sum_{s \in S_{tm}}  (P^{p}_{s} - P^{p}_{d}) y^{s}_{tm} f^{out}_{tm} \leq 0, \ \ \  a \in A^{t}, d \in D_a, p = \{p \in P^{res}_b | b \in P_a \cap P^{blend}\}$$

5. Bound quality constraints
$$ \sum_{tm \in M^{+}_a | d \in D_a} \sum_{s \in S_{tm}} (P^{k}_{s} - P^{k}_{d}) y^{s}_{tm} f^{out}_{tm} \leq 0, d \in D, k \in K$$




## Notation
$L^{trans}$: Transmission
$M$: Transmission modes
$M^{+}_{tm}$: Transmission modes injecting to $tm$ through an area. It only includes $tm'$ sharing `Resource` with $tm$
$M^{+}_{a}$: Transmission modes injecting to $a$
$S_{tm}$: Sources linked to $tm$. These include: i) sources linked to $tm' \in M^{+}_{tm}$ and ii) sources from $A^{+}_{tm}$ which share product with $tm$. Sharing product here means either they supply the same `ResourceCarrier`or supply `ResourceCarriers` composing the `ResourceBlend` into a `RefBlending`node.
$A$: Areas
$A^{+}_{tm}$: Singleton of the area injecting to $tm$
$A^{t}$: Areas without Out-neighbouring areas. This Areas are only allowed to contain a `Sink`node.
$P_{a}$: Products exchanged in an area
$P_{l}, P_{tm}, P_{s}$: Product associated to a link, trasmission mode, source...
$b \in P^{blend}$: `ResourceBlend`
$P^{res}$: `ResourceCarrier`
$P^{res}_{b}$: `ResourceCarrier` forming `ResourceBlend` $b$ 
$G_{a}$: GeoAvailability node in $a$
$D$: `RefBlendingSink` nodes
$D_{a}$: `RefBlendingSink` nodes in $a$
$K$: Components (e.g., Sulfur)


$b_i$: Max. outflow of area $i$

#### TODO
- How the model is now there is no possibility of setting a bound of **qualities** to products that are not blended. 
