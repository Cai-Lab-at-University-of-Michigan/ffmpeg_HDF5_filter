/*****************************************************************************
 * Copyright by The HDF Group.                                               *
 * All rights reserved.                                                      *
 *                                                                           *
 * This file is part of the HDF Java Products distribution.                  *
 * The full copyright notice, including terms governing use, modification,   *
 * and redistribution, is contained in the COPYING file, which can be found  *
 * at the root of the source code distribution tree,                         *
 * or in https://www.hdfgroup.org/licenses.                                  *
 * If you do not have access to either file, you may request a copy from     *
 * help@hdfgroup.org.                                                        *
 ****************************************************************************/

package hdf.object;

/**
 * An interface that provides general operations for data with a Compound
 * datatype. For example, getting the names, dataspaces or datatypes of the
 * members of the Compound datatype.
 *
 * @see hdf.object.HObject
 *
 * @version 1.0 5/3/2018
 * @author Jordan T. Henderson
 */
public interface CompoundDataFormat extends DataFormat
{
    /**
     * Returns the number of members of the compound data object.
     *
     * @return the number of members of the compound data object.
     */
    int getMemberCount();

    /**
     * Returns the number of selected members of the compound data object.
     *
     * Selected members are the compound fields which are selected for read/write.
     *
     * For example, in a compound datatype of {int A, float B, char[] C}, users can
     * choose to retrieve only {A, C} from the data object. In this case,
     * getSelectedMemberCount() returns two.
     *
     * @return the number of selected members.
     */
    int getSelectedMemberCount();

    /**
     * Returns the names of the members of the compound data object. The names of
     * compound members are stored in an array of Strings.
     *
     * For example, for a compound datatype of {int A, float B, char[] C}
     * getMemberNames() returns ["A", "B", "C"}.
     *
     * @return the names of compound members.
     */
    String[] getMemberNames();

    /**
     * Returns an array of the names of the selected compound members.
     *
     * @return an array of the names of the selected compound members.
     */
    String[] getSelectedMemberNames();

    /**
     * Checks if a member of the compound data object is selected for read/write.
     *
     * @param idx
     *            the index of compound member.
     *
     * @return true if the i-th memeber is selected; otherwise returns false.
     */
    boolean isMemberSelected(int idx);

    /**
     * Selects the i-th member for read/write.
     *
     * @param idx
     *            the index of compound member.
     */
    void selectMember(int idx);

    /**
     * Selects/deselects all members.
     *
     * @param selectAll
     *            The indicator to select or deselect all members. If true, all
     *            members are selected for read/write. If false, no member is
     *            selected for read/write.
     */
    void setAllMemberSelection(boolean selectAll);

    /**
     * Returns array containing the total number of elements of the members of the
     * compound data object.
     *
     * For example, a compound dataset COMP has members of A, B and C as
     *
     * <pre>
     *     COMP {
     *         int A;
     *         float B[5];
     *         double C[2][3];
     *     }
     * </pre>
     *
     * getMemberOrders() will return an integer array of {1, 5, 6} to indicate that
     * member A has one element, member B has 5 elements, and member C has 6
     * elements.
     *
     * @return the array containing the total number of elements of the members of
     *         the compound data object.
     */
    int[] getMemberOrders();

    /**
     * Returns array containing the total number of elements of the selected members
     * of the compound data object.
     *
     * For example, a compound dataset COMP has members of A, B and C as
     *
     * <pre>
     *     COMP {
     *         int A;
     *         float B[5];
     *         double C[2][3];
     *     }
     * </pre>
     *
     * If A and B are selected, getSelectedMemberOrders() returns an array of {1, 5}
     *
     * @return array containing the total number of elements of the selected members
     *         of the compound data object.
     */
    int[] getSelectedMemberOrders();

    /**
     * Returns the dimension sizes of the i-th member.
     *
     * For example, a compound dataset COMP has members of A, B and C as
     *
     * <pre>
     *     COMP {
     *         int A;
     *         float B[5];
     *         double C[2][3];
     *     }
     * </pre>
     *
     * getMemberDims(2) returns an array of {2, 3}, while getMemberDims(1) returns
     * an array of {5}, and getMemberDims(0) returns null.
     *
     * @param i
     *            the i-th member
     *
     * @return the dimension sizes of the i-th member, null if the compound member
     *         is not an array.
     */
    int[] getMemberDims(int i);

    /**
     * Returns an array of datatype objects of the compound members.
     *
     * Each member of a compound data object has its own datatype. The datatype of a
     * member can be atomic or other compound datatype (nested compound). The
     * datatype objects are setup at init().
     *
     * @return the array of datatype objects of the compound members.
     */
    Datatype[] getMemberTypes();

    /**
     * Returns an array of datatype objects of the selected compound members.
     *
     * @return an array of datatype objects of the selected compound members.
     */
    Datatype[] getSelectedMemberTypes();

}
